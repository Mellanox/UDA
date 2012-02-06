/*
** Copyright (C) Mellanox Technologies Ltd. 2001-2011.  ALL RIGHTS RESERVED.
**
** This software product is a proprietary product of Mellanox Technologies Ltd.
** (the "Company") and all right, title, and interest in and to the software product,
** including all associated intellectual property rights, are and shall
** remain exclusively with the Company.
**
** This software product is governed by the End User License Agreement
** provided with the software product.
**
*/

#include <stdio.h>
#include <sys/socket.h>
#include <sys/epoll.h>
#include <malloc.h>
#include <netdb.h>
#include <errno.h>

#include <infiniband/verbs.h>
#include <rdma/rdma_cma.h>

#include "RDMAClient.h"
#include "../Merger/InputClient.h"
#include "../include/IOUtility.h"
using namespace std;

extern int netlev_dbg_flag;
extern merging_state_t merging_sm; 
extern uint32_t wqes_perconn;


static void 
client_comp_ibv_recv(netlev_wqe_t *wqe)
{
    struct ibv_send_wr *bad_sr;
    struct ibv_recv_wr *bad_rr;

    netlev_msg_t  *h = (netlev_msg_t *)wqe->data;
    netlev_conn_t *conn = wqe->conn;

    /* credit flow */
    pthread_mutex_lock(&conn->lock);
    conn->credits += h->credits; /* credits from peer */

    /* sanity check */
    if (conn->credits > wqes_perconn - 1) {
    	log(lsERROR, "credit overflow. credits are %d", conn->credits);
        conn->credits = wqes_perconn - 1;
    }

    h->credits = 0;

    /* empty backlog */
    while (conn->credits > 0 && !list_empty(&conn->backlog)) {
    	netlev_msg_backlog_t *back = list_entry(conn->backlog.next, typeof(*back), list);
    	list_del(&back->list);
    	netlev_msg_t h_back;
    	h_back.credits = conn->returning;
		conn->returning = 0;

		h_back.type = back->type;
		h_back.tot_len = back->len;
		h_back.src_req = back->src_req ? back->src_req : 0;
		memcpy(h_back.msg, back->msg, back->len);
    	int len = sizeof(netlev_msg_t)-(NETLEV_FETCH_REQSIZE-back->len);
	    struct ibv_send_wr send_wr;
	    ibv_sge sg ;
	    bool send_signal = !(conn->sent_counter%SIGNAL_INTERVAL);
	    conn->sent_counter++;
    	init_wqe_send(&send_wr, &sg, &h_back, len, send_signal, back->context);

        conn->credits--;

        log(lsTRACE, "removing a wqe from backlog");
        if (ibv_post_send(conn->qp_hndl, &send_wr, &bad_sr)) {
            output_stderr("[%s,%d] Error posting send\n",
                          __FILE__,__LINE__);
        }
        free(back->msg);
        free(back);
    }
    pthread_mutex_unlock(&conn->lock);

    if ( h->type == MSG_RTS ) {
    	client_part_req_t *req = (client_part_req_t*) (long2ptr(h->src_req));
        memcpy(req->recvd_msg, h->msg, h->tot_len);

        log(lsTRACE, "Client received RDMA completion for fetch request: jobid=%s, mapid=%s, reducer_id=%s, total_fetched=%lld (not updated for this comp)", req->info->params[1], req->info->params[2], req->info->params[3], req->mop->total_fetched);
        merging_sm.client->rdma->fetch_over(req); 
    } 
    else {
    	log(lsDEBUG, "received a noop");
    }

    
    /* put the receive wqe back */
    init_wqe_recv(wqe, NETLEV_FETCH_REQSIZE, conn->mem->mr->lkey, conn);
    // TODO: this log might be too verbose
    log(lsTRACE, "ibv_post_recv");
    if (ibv_post_recv(conn->qp_hndl, &wqe->desc.rr, &bad_rr)) {
        output_stderr("[%s,%d] ibv_post_recv failed\n",
                      __FILE__,__LINE__);
    }
    pthread_mutex_lock(&conn->lock);
    conn->returning++;
    pthread_mutex_unlock(&conn->lock);

    /* Send a no_op for credit flow */
    if (conn->returning >= (conn->peerinfo.credits >> 1)) {
    	netlev_msg_t h;
    	log(lsDEBUG, "sending a noop");
    	netlev_post_send(&h,  0, 0, NULL, conn, MSG_NOOP);
    }
}



static void 
client_cq_handler(progress_event_t *pevent, void *data)
{
    int rc=0;
	int ne = 0;
    struct ibv_wc desc;
    void *ctx;
    netlev_wqe_t *wqe = NULL;
    netlev_dev_t *dev = (netlev_dev_t *) pevent->data;

    if ((rc = ibv_get_cq_event(dev->cq_channel, &dev->cq, &ctx)) != 0) {
        output_stderr("[%s,%d] notification, but no CQ event or bad rc=%d \n", __FILE__,__LINE__, rc);
        goto error_event;
    }

    ibv_ack_cq_events(dev->cq, 1);

    do {
        ne = ibv_poll_cq(dev->cq, 1, &desc);

		if ( ne < 0) {
			log(lsERROR, "ibv_poll_cq failed ne=%d, (errno=%d %m)", ne, errno);
			return;
		}

        if (ne) {
            if (desc.status != IBV_WC_SUCCESS) {
                if (desc.status == IBV_WC_WR_FLUSH_ERR) {
                    output_stderr("Operation: %s. Dev %p wr flush err. quitting...",
                                  netlev_stropcode(desc.opcode), dev);
                    goto error_event;
                } else {
                    output_stderr("Operation: %s. Bad WC status %d for wr_id 0x%llx",
							netlev_stropcode(desc.opcode), desc.status,
                                  (unsigned long long) desc.wr_id);
                    goto error_event;
                }
            } else {

				/* output_stdout("Detect cq event wqe=%p, opcode=%d",
                              wqe, desc.opcode); */

                switch (desc.opcode) {

                    case IBV_WC_SEND:
                    	log(lsTRACE, "IBV_WC_SEND");
                        break;

                    case IBV_WC_RECV:
                    	wqe = (netlev_wqe_t *) (long2ptr(desc.wr_id));
                    	log(lsTRACE, "rdma client got IBV_WC_RECV local_qp=%d, remote_qp=%d", wqe->conn->qp_hndl->qp_num, wqe->conn->peerinfo.qp);
                        client_comp_ibv_recv(wqe);
                        break;

                    default:
					output_stderr("id %llx status %d unknown opcode %d",
							desc.wr_id,
							desc.status,
                                      desc.opcode);
                        break;
                }
            }
            /* output_stdout("Complete event wr_id=0x%lx", desc.wr_id); */
        }
    } while (ne);

	error_event:

	if (ibv_req_notify_cq(dev->cq, 0) != 0) {
        output_stderr("[%s,%d] ibv_req_notify_cq failed\n",
                      __FILE__,__LINE__);
    }

    return;
}


netlev_conn_t*
netlev_get_conn(unsigned long ipaddr, int port, 
                netlev_ctx_t *ctx, 
                list_head_t *registered_mem)
{
    netlev_conn_t         *conn;
    struct rdma_cm_event  *event;
    struct rdma_cm_id     *cm_id;
    struct netlev_dev     *dev;
    struct sockaddr_in     sin;
    struct rdma_conn_param conn_param;
    struct connreq_data    xdata;
    int rc=0;
    errno = 0;

    sin.sin_addr.s_addr = ipaddr;
    sin.sin_family = AF_INET;
    sin.sin_port = htons(port);

    if (rdma_create_id(ctx->cm_channel, &cm_id, NULL, RDMA_PS_TCP) != 0) {
    	log(lsFATAL, "rdma_create_id failed, (errno=%d %m)",errno);
        return NULL;
    }

    if (rdma_resolve_addr(cm_id, NULL, (struct sockaddr*)&sin, NETLEV_TIMEOUT_MS)) {
    	log(lsFATAL, "rdma_resolve_addr failed, (errno=%d %m)",errno);
        return NULL;
    }

    if (rdma_get_cm_event(ctx->cm_channel, &event)) {
    	log(lsFATAL, "rdma_get_cm_event failed, (errno=%d %m)",errno);
        return NULL;
    }


    if (event->event != RDMA_CM_EVENT_ADDR_RESOLVED) {
        rdma_ack_cm_event(event);
        log(lsFATAL, "unexpected CM event %d", event->event);
        return NULL;
    }
    rdma_ack_cm_event(event);

    if (rdma_resolve_route(cm_id, NETLEV_TIMEOUT_MS)) {
    	log(lsFATAL, "rdma_resolve_route failed, (errno=%d %m)",errno);
        return NULL;
    }

    if (rdma_get_cm_event(ctx->cm_channel, &event)) {
    	log(lsFATAL, "rdma_get_cm_event failed, (errno=%d %m)",errno);
        return NULL;
	}

    if (event->event != RDMA_CM_EVENT_ROUTE_RESOLVED) {
        rdma_ack_cm_event(event);
        log(lsERROR, "unexpected CM event %d", event->event);
        return NULL;
    }
    rdma_ack_cm_event(event);

    dev = netlev_dev_find(cm_id, &ctx->hdr_dev_list);
    if (!dev) {
        dev = (netlev_dev_t*) malloc(sizeof(netlev_dev_t));
        if (dev == NULL) {
        	log(lsFATAL, "failed to allocate memory for netlev_dev");
            return NULL;
        }
        dev->ibv_ctx = cm_id->verbs; 
        if ( netlev_dev_init(dev) != 0) {
            free(dev);
            return NULL;
        }
     
        struct memory_pool *mem_pool = NULL;
        list_for_each_entry(mem_pool, registered_mem, register_mem_list) {
            rc = netlev_init_rdma_mem(mem_pool->mem, mem_pool->total_size, dev);
            if (rc) {
                log(lsFATAL, "FATAL ERROR: failed on netlev_init_rdma_mem , rc=%d ==> exit process", rc);
                exit(rc);
            }
        }

                 
        netlev_event_add(ctx->epoll_fd, dev->cq_channel->fd, 
                         EPOLLIN, client_cq_handler, 
                         dev, &ctx->hdr_event_list);

        list_add_tail(&dev->list, &ctx->hdr_dev_list);
    } else {
    	log(lsDEBUG, "device found");
    }

    conn = netlev_conn_alloc(dev, cm_id);
    if (!conn) {
        goto err_conn_alloc; 
    }

    /* Save an extra one for credit flow */
    memset(&xdata, 0, sizeof(xdata));
    xdata.qp = cm_id->qp->qp_num;
    xdata.credits = wqes_perconn - 1;
    xdata.rdma_mem_rkey = dev->rdma_mem->mr->rkey;

    memset(&conn_param, 0, sizeof (conn_param));
    conn_param.responder_resources = 1;
    conn_param.initiator_depth = 1;
    conn_param.retry_count = RDMA_DEFAULT_RNR_RETRY;
    conn_param.rnr_retry_count = RDMA_DEFAULT_RNR_RETRY;
    conn_param.private_data = &xdata;
    conn_param.private_data_len = sizeof(xdata);

    if (rdma_connect(cm_id, &conn_param)) {
    	log(lsERROR, "rdma_connect failed, (errno=%d %m)",errno);
        goto err_rdma_connect;
    }

    if (rdma_get_cm_event(ctx->cm_channel, &event)) {
    	log(lsERROR, "rdma_get_cm_event err, (errno=%d %m)",errno);
        goto err_rdma_connect;
    }

    if (event->event == RDMA_CM_EVENT_ESTABLISHED) {
    	log(lsINFO, "Successfully got RDMA_CM_EVENT_ESTABLISHED with peer %x:%d", (int)ipaddr, port);
        conn->peerIPAddr = ipaddr;
        list_add_tail(&conn->list, &ctx->hdr_conn_list);

        if (!event->param.conn.private_data || 
            (event->param.conn.private_data_len < sizeof(conn->peerinfo))) { 
            output_stderr("%s: bad private data len %d",
                          __func__, event->param.conn.private_data_len);
        }
        memcpy(&conn->peerinfo, event->param.conn.private_data, sizeof(conn->peerinfo));
        conn->credits = conn->peerinfo.credits;
        log(lsDEBUG,"Client conn->credits in the beginning is %d", conn->credits);
        conn->returning = 0;
        rdma_ack_cm_event(event);
    } else {
        output_stderr("[%s,%d] client recv unknown event %d",
                      __FILE__,__LINE__, event->event);
        rdma_ack_cm_event(event);
        goto err_rdma_connect;
    }
    return conn;

err_rdma_connect:
    netlev_conn_free(conn);
err_conn_alloc:
    rdma_destroy_id(cm_id);
    rdma_destroy_event_channel(ctx->cm_channel);
    output_stderr("[%s,%d] connection failed",
                 __FILE__,__LINE__);
    return NULL;
};


RdmaClient::RdmaClient(int port, merging_state_t *state)
{
    netlev_thread_t *th;

    memset(&this->ctx, 0, sizeof(netlev_ctx_t));
    pthread_mutex_init(&this->ctx.lock, NULL);
    INIT_LIST_HEAD(&this->ctx.hdr_event_list);
    INIT_LIST_HEAD(&this->ctx.hdr_dev_list);
    INIT_LIST_HEAD(&this->ctx.hdr_conn_list);
    INIT_LIST_HEAD(&this->register_mems_head); 
    errno = 0;

    this->state = state;
    this->parent = state->client;
    this->svc_port = port;
    this->ctx.cm_channel = rdma_create_event_channel();

    if (!this->ctx.cm_channel)  {
        log(lsFATAL, "rdma_create_event_channel failed, (errno=%d %m)",errno);
    }

    this->ctx.epoll_fd = epoll_create(4096);

    if (this->ctx.epoll_fd < 0) {
    	log(lsFATAL, "cannot create epoll fd, (errno=%d %m)",errno);
    }

    /* Start a new thread */
    memset(&this->helper, 0, sizeof(this->helper));
    th = &this->helper;
    th->stop = 0;
    th->pollfd = this->ctx.epoll_fd;
    pthread_attr_init(&th->attr);
    pthread_attr_setdetachstate(&th->attr, PTHREAD_CREATE_JOINABLE);
    log(lsINFO, "CREATING THREAD"); pthread_create(&th->thread, &th->attr, event_processor, th);

    /* FIXME: 
     * When we consider disconnection we need to add 
     * the cm_event channel to the epoll descriptor.  
     */
}

RdmaClient::~RdmaClient()
{
    struct netlev_conn *conn;
    struct netlev_dev *dev;
    

    /* relase all connection */
    while(!list_empty(&this->ctx.hdr_conn_list)) {
        conn = list_entry(this->ctx.hdr_conn_list.next, typeof(*conn), list);
        log(lsDEBUG,"Client conn->credits is %d", conn->credits);
        netlev_conn_free(conn);
    }
    //DBGPRINT(DBG_CLIENT, "all connections are released\n");

    /* release all device */
    while(!list_empty(&this->ctx.hdr_dev_list)) {
        dev = list_entry(this->ctx.hdr_dev_list.next, typeof(*dev), list);
        list_del(&dev->list);
        netlev_event_del(this->ctx.epoll_fd, dev->cq_channel->fd,
                         &this->ctx.hdr_event_list);
        netlev_dev_release(dev);
        free(dev);
    }
    //DBGPRINT(DBG_CLIENT, "all devices are released\n");

    this->helper.stop = 1;
    pthread_attr_destroy(&this->helper.attr);
    pthread_join(this->helper.thread, NULL); log(lsINFO, "THREAD JOINED");
    //DBGPRINT(DBG_CLIENT, "RDMAClient is shut down \n");

    rdma_destroy_event_channel(this->ctx.cm_channel);
    close(this->ctx.epoll_fd);
    pthread_mutex_destroy(&this->ctx.lock);
}

void
RdmaClient::disconnect(struct netlev_conn *conn)
{
    rdma_disconnect(conn->cm_id);
    netlev_conn_free(conn);
}

void 
RdmaClient::register_mem(struct memory_pool *mem_pool)
{
    struct netlev_dev *dev = NULL;
    list_for_each_entry(dev, &this->ctx.hdr_dev_list, list) {
        netlev_init_rdma_mem(mem_pool->mem, mem_pool->total_size, dev);
    }
    list_add_tail(&mem_pool->register_mem_list, &this->register_mems_head);
}

netlev_conn_t* 
RdmaClient::connect(const char *host, int port)
{
    netlev_conn_t *conn;
    unsigned long ipaddr;

    pthread_mutex_lock(&this->ctx.lock);
    ipaddr = get_hostip(host);
    if (!ipaddr) {
        output_stderr("get hostip error");
        pthread_mutex_unlock(&this->ctx.lock);
        return NULL;
    }
    conn = netlev_find_conn_by_ip(ipaddr, &this->ctx.hdr_conn_list);
    if (conn) {
        pthread_mutex_unlock(&this->ctx.lock);
        return conn;
    }

    output_stdout("RDMA Client: connecting to %s:%d" , host, port);

    conn = netlev_get_conn(ipaddr, port, &this->ctx, &this->register_mems_head);

    if (!conn) {
        output_stderr("connection to %d failed", host);
    }

    pthread_mutex_unlock(&this->ctx.lock);
    
    return conn;
}

int
RdmaClient::fetch_over(client_part_req_t *freq)
{
    this->parent->comp_fetch_req(freq);
    return 0;
}


int 
RdmaClient::fetch(client_part_req_t *freq) 
{
    int             msg_len;
    uint64_t        addr;
    netlev_conn_t  *conn;

    int idx = freq->mop->staging_mem_idx; 
    addr = (uint64_t)((uintptr_t)(freq->mop->mop_bufs[idx]->buff));

    netlev_msg_t h;

    /* jobid:mapid:mop_offset:reduceid:mem_addr */
    msg_len = sprintf(h.msg,"%s:%s:%ld:%s:%lu:%lu",
                      freq->info->params[1],
                      freq->info->params[2],
                      freq->mop->total_fetched,
                      freq->info->params[3],
                      addr,(uint64_t) freq);

    conn = connect(freq->info->params[0], svc_port);
    if (!conn) return -1; //log was already issued inside connect
    log(lsTRACE, "calling to netlev_post_send: mapid=%s, reduceid=%s, mapp_offset=%lld, qp=%d, hostname=%s", freq->info->params[2], freq->info->params[3], freq->mop->total_fetched, conn->qp_hndl->qp_num,freq->info->params[0]);

    log(lsTRACE, "msg len is %d", msg_len);
    return netlev_post_send(&h,  msg_len, 0, freq, conn, MSG_RTS);


}



unsigned long 
RdmaClient::get_hostip (const char *host)
{
    string id(host);
    map<string, unsigned long>::iterator iter;
    iter = this->local_dns.find(id);
    if (iter != this->local_dns.end()) {
        return iter->second;
    }
    
    struct addrinfo *res;
    struct addrinfo  hints;
    unsigned long    ip;

    memset(&hints, 0, sizeof(hints));
    hints.ai_family   = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    if ((getaddrinfo(host, NULL, &hints, &res)) < 0 ) {
        output_stderr("%s: getaddr for %s", 
                      __func__, host);
        ip = 0;
    } else {
        ip = ((struct sockaddr_in*)res->ai_addr)->sin_addr.s_addr;
    }
    freeaddrinfo(res);
    local_dns[id] = ip;
    return ip;
}
/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
