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
#include <unistd.h>
#include <sys/socket.h>
#include <sys/epoll.h>
#include <malloc.h>
#include <errno.h>
#include <stdint.h>
#include <stdlib.h>

#include <infiniband/verbs.h>
#include <rdma/rdma_cma.h>

#include "RDMAServer.h"
#include "../MOFServer/MOFServlet.h"
#include "../include/IOUtility.h"

using namespace std;

extern supplier_state_t state_mac;

static void 
server_comp_ibv_send(netlev_wqe_t *wqe)
{
    hdr_header_t *h = (hdr_header_t *)wqe->data;
    netlev_conn_t *conn = wqe->conn;
    netlev_dev *dev = conn->dev;
  
    if (h->type == MSG_RTS) { 
        if (wqe->shreq) {
                state_mac.mover->insert_incoming_req(wqe->shreq);
                wqe->shreq = NULL;
        }
    }
    
    pthread_mutex_lock(&dev->lock);
    release_netlev_wqe(wqe, &dev->wqe_list);
    
    /* Send a no_op for credit flow */
    if (conn->returning >= (conn->peerinfo.credits >> 1)) {
        netlev_send_noop(conn);
    }
    pthread_mutex_unlock(&dev->lock);

}

static void 
server_comp_ibv_recv(netlev_wqe_t *wqe)
{
    struct ibv_send_wr *bad_sr;
    struct ibv_recv_wr *bad_rr;

    hdr_header_t  *h = (hdr_header_t*)wqe->data;
    netlev_conn_t *conn = wqe->conn;
    netlev_dev_t  *dev = conn->dev;

    /* Credit flow */
    pthread_mutex_lock(&conn->lock);
    conn->credits += h->credits; /* Credits from peer */

    /* sanity check */
    if (conn->credits > NETLEV_WQES_RECV_PERCONN - 1) {
        /* output_stderr("[%s,%d] credit overflow", 
                      __FILE__,__LINE__); */
        conn->credits = NETLEV_WQES_RECV_PERCONN - 1;
    }
    
    h->credits = 0;

    while (conn->credits > 0 && !list_empty(&conn->backlog)) {
        netlev_wqe_t *w;
        hdr_header_t *bh;

        conn->credits --;
        w = list_entry(conn->backlog.next, typeof(*w), list);
        list_del(&w->list);
        bh = (hdr_header_t *)w->data;

        if (conn->returning) {
            bh->credits = conn->returning;
            conn->returning = 0;
        }
        
        if (ibv_post_send(conn->qp_hndl, &(w->desc.sr), &bad_sr)) {
            output_stderr("[%s,%d] Error posting send",
                          __FILE__,__LINE__);
        }
    } 
    pthread_mutex_unlock(&conn->lock);

    if (h->type == MSG_RTS) {
        shuffle_req_t *data_req;
        string param((char *)(h + 1), h->tot_len);
        
        /* XXX: create a free list of request to avoid malloc/free */
        data_req = get_shuffle_req(param);
        data_req->conn = conn;
        data_req->peer_wqe = (void *)h->src_wqe;

        /* pass to parent and wake up other threads for processing */
        state_mac.mover->insert_incoming_req(data_req);
    
    } 

    /* re-post wqe */
    wqe->state = RECV_WQE_COMP; 
    /* Return the wqe of a noop message, recv */
    init_wqe_recv(wqe, NETLEV_FETCH_REQSIZE, dev->mem->mr->lkey, conn);
    if (ibv_post_recv(conn->qp_hndl, &wqe->desc.rr, &bad_rr)) {
        output_stderr("[%s,%d] ibv_post_recv failed",
                      __FILE__,__LINE__);
    }

    pthread_mutex_lock(&conn->lock);
    conn->returning ++;
    pthread_mutex_unlock(&conn->lock);

    pthread_mutex_lock(&dev->lock);
    /* Send a no_op for credit flow */
    if (conn->returning >= (conn->peerinfo.credits >> 1)) {
        netlev_send_noop(conn);
    }
    pthread_mutex_unlock(&dev->lock);
}

static void server_cq_handler(progress_event_t *pevent, void *data)
{
    struct ibv_wc desc;
    netlev_wqe_t *wqe = NULL;
    int ne = 0;

    struct netlev_dev *dev = (netlev_dev_t *)data;

    void *ctx;
    if (ibv_get_cq_event(dev->cq_channel, &dev->cq, &ctx) != 0) {
        output_stderr("[%s,%d] notification, but no CQ event\n",
                      __FILE__,__LINE__);
        goto error_event;
    }

    ibv_ack_cq_events(dev->cq, 1);

    if (ibv_req_notify_cq(dev->cq, 0)) {
        output_stderr("[%s,%d] ibv_req_notify_cq failed\n",
                      __FILE__,__LINE__);
        goto error_event;
    }

    do {
        ne = ibv_poll_cq(dev->cq, 1, &desc);

        if (ne) {
            if (desc.status != IBV_WC_SUCCESS) {
                if (desc.status == IBV_WC_WR_FLUSH_ERR) {
                    output_stderr("Operation: %s. Dev %p wr (0x%llx) flush err. quitting...",
                                  netlev_stropcode(desc.opcode), dev, 
                                  (unsigned long long)desc.wr_id);
                    goto error_event;
                } else {
                    output_stderr("Operation: %s. Bad WC status %d for wr_id 0x%llx\n",
                                  netlev_stropcode(desc.opcode), desc.status, 
                                  (unsigned long long) desc.wr_id);
                    goto error_event;
                }
            } else {
            	wqe = (netlev_wqe_t *) (long2ptr(desc.wr_id));

                switch (desc.opcode) {

                    case IBV_WC_SEND:
                        server_comp_ibv_send(wqe);
                        break;

                    case IBV_WC_RECV:
                        server_comp_ibv_recv(wqe);
                        break;

                    case IBV_WC_RDMA_WRITE:
                        state_mac.data_mac->release_chunk((chunk_t*)wqe->context);

                        pthread_mutex_lock(&dev->lock);
                        release_netlev_wqe(wqe, &dev->wqe_list);
                        pthread_mutex_unlock(&dev->lock);

                        break;

                    case IBV_WC_RDMA_READ:
                    default:
                        output_stderr("%s: id %llx status %d unknown opcode %d\n",
                                      __func__, desc.wr_id, desc.status, desc.opcode);
                        break;
                }
            }
        }
    } while (ne);

error_event:
    return;
}


static void 
server_cm_handler(progress_event_t *pevent, void *data)
{
    int ret;

    struct netlev_ctx    *ctx;
    struct rdma_cm_event *cm_event;
    struct netlev_conn   *conn = 0;
    struct netlev_dev    *dev;
    RdmaServer           *server;

    server = (RdmaServer *)data;
    ctx    = &(server->ctx);

    struct rdma_event_channel *cm_channel = ctx->cm_channel;
    RdmaServer *rdma_server = (RdmaServer *)pevent->data;

    if (rdma_get_cm_event(cm_channel, &cm_event)) {
        output_stderr("[%s:%d] rdma_get_cm_event err",
                      __FILE__, __LINE__);
        return;
    }

    log(lsDEBUG, "got rdma event = %d", cm_event->event);

    switch (cm_event->event) {
        case RDMA_CM_EVENT_CONNECT_REQUEST:
            {
                dev = netlev_dev_find(cm_event->id, 
                                      &ctx->hdr_dev_list); 

                log(lsTRACE, "got RDMA_CM_EVENT_CONNECT_REQUEST; found dev=%x", dev);

                if (!dev) {
                    dev = (struct netlev_dev *) malloc(sizeof(struct netlev_dev));
                    memset(dev, 0, sizeof(struct netlev_dev));
                    if (dev == NULL) {
                        output_stderr("[%s,%d] alloc dev failed",
                                     __FILE__,__LINE__);
                        return;
                    }
                    dev->ibv_ctx = cm_event->id->verbs; 
                    if (netlev_dev_init(dev) != 0) {
                        log(lsWARN, "netlev_dev_init failed");
                        free(dev);
                        return;
                    }
                    
                    ret = netlev_init_rdma_mem(rdma_server->rdma_mem, 
                                               rdma_server->rdma_total_len,
                                               dev);
                    if (ret) {
                        log(lsWARN, "netlev_init_rdma_mem failed");
                        free(dev);
                        return;
                    }

                    ret = netlev_event_add(ctx->epoll_fd,
                                           dev->cq_channel->fd, 
                                           EPOLLIN, server_cq_handler, 
                                           dev, &ctx->hdr_event_list);
                    if (ret) {
                        log(lsWARN, "netlev_event_add failed");
                        free(dev);
                        return;
                    }

                    pthread_mutex_lock(&ctx->lock);
                    list_add_tail(&dev->list, &ctx->hdr_dev_list);
                    pthread_mutex_unlock(&ctx->lock);
                }

                conn = netlev_init_conn(cm_event, dev);
                log(lsTRACE, "conn=%x", conn);
                if (!cm_event->param.conn.private_data || 
                    (cm_event->param.conn.private_data_len < sizeof(conn->peerinfo))) 
                {
                    log(lsERROR, "bad private data len %d", cm_event->param.conn.private_data_len);
                }

                memcpy(&conn->peerinfo, cm_event->param.conn.private_data, 
                        sizeof(conn->peerinfo));
                conn->credits = conn->peerinfo.credits;
                conn->returning = 0;

                conn->state = NETLEV_CONN_RTR;
                pthread_mutex_lock(&ctx->lock);
                list_add_tail(&conn->list, &ctx->hdr_conn_list);
                pthread_mutex_unlock(&ctx->lock);
            }
            break;

        case RDMA_CM_EVENT_ESTABLISHED:
            conn = netlev_conn_established(cm_event, &ctx->hdr_conn_list);
            log(lsDEBUG, "RDMA_CM_EVENT_ESTABLISHED - netlev_conn_established returned conn=%x", conn);
            break;

        case RDMA_CM_EVENT_DISCONNECTED:
            log(lsDEBUG, "got RDMA_CM_EVENT_DISCONNECTED");

/*
 	 AVNER:
 	 	 	 temp - put orig cleanup code because it makes the RDMA server unusable
 	 	 	 see also: http://redmine.lab.mtl.com/redmine/issues/4533
 	 	 	 TODO: currently there is resource leak

            conn = netlev_disconnect(cm_event, &ctx->hdr_conn_list);

            if (conn) {
                pthread_mutex_lock(&ctx->lock);
                list_del(&conn->list);
                pthread_mutex_unlock(&ctx->lock);
            }
//*/

            log(lsWARN, "only destroying qp.  No real cleanup.  This is resource leak!");
            rdma_destroy_qp(cm_event->id);

            break;
        case RDMA_CM_EVENT_TIMEWAIT_EXIT:  // avner: don't bail out
            log(lsWARN, "got RDMA_CM_EVENT_TIMEWAIT_EXIT");
            // TODO: consider cleanup
            break;

        default:
            log(lsFATAL, "Server got unknown event %d, bailing out", cm_event->event);
            if (cm_event->id) {
                if (rdma_destroy_id(cm_event->id)){
                    log(lsERROR, "rdma_destroy_id failed");
                }
            }
            /* XXX: Trigger the exit of all threads */
            exit (1);
            break;
    }

    log(lsTRACE, "calling rdma_ack_cm_event for event=%d", cm_event->event);
    ret = rdma_ack_cm_event(cm_event);
    if (ret) {
        output_stderr("ack cm event failed");
    }
}


RdmaServer::RdmaServer(int port, int rdma_buf_size, void *state)

{
    supplier_state_t *smac = (supplier_state_t *)state;
    
    memset(&this->ctx, 0, sizeof(netlev_ctx_t));
    pthread_mutex_init(&this->ctx.lock, NULL);
    INIT_LIST_HEAD(&this->ctx.hdr_event_list);
    INIT_LIST_HEAD(&this->ctx.hdr_dev_list);
    INIT_LIST_HEAD(&this->ctx.hdr_conn_list);

    this->data_port = port;
    this->parent   = smac->mover;
    this->data_mac = smac->data_mac;
    
    int rdma_align = getpagesize();
    this->rdma_total_len = NETLEV_RDMA_MEM_CHUNKS_NUM * (rdma_buf_size + 2*AIO_ALIGNMENT);
    this->rdma_chunk_len = rdma_buf_size + 2*AIO_ALIGNMENT;
    log(lsDEBUG, "rdma_buf_size inside RdmaServer is %d\n", rdma_buf_size);

    this->rdma_mem = (void *) memalign(rdma_align, this->rdma_total_len);
    if (!this->rdma_mem) {
        output_stderr("[%s,%d] alloc rdma buf failed",
                      __FILE__,__LINE__);
    }
    log(lsDEBUG, "memalign successed - %llu bytes", this->rdma_total_len);

}

void 
RdmaServer::start_server()
{
    netlev_thread_t *th;

    this->ctx.epoll_fd = epoll_create(4096);
    if (this->ctx.epoll_fd < 0) {
        output_stderr("Cannot create epoll fd");
    }

    /* Start a new thread */
    memset(&this->helper, 0, sizeof(this->helper));
    th = &this->helper;
    th->stop = 0;
    th->pollfd = this->ctx.epoll_fd;

    this->create_listener();

    pthread_attr_init(&th->attr);
    pthread_attr_setdetachstate(&th->attr, PTHREAD_CREATE_JOINABLE);
    pthread_create(&th->thread, &th->attr, event_processor, th);
}

RdmaServer::~RdmaServer()
{
    pthread_mutex_destroy(&this->ctx.lock);
    this->parent  = NULL;
    this->data_mac = NULL;
    free(this->rdma_mem);
}

void 
RdmaServer::stop_server()
{
    struct netlev_conn *conn;
    struct netlev_dev  *dev;
    void *pstatus;

    this->destroy_listener();

    pthread_mutex_lock(&this->ctx.lock);

    while (!list_empty(&this->ctx.hdr_conn_list)) {
        conn = list_entry(this->ctx.hdr_conn_list.next, typeof(*conn), list);
        netlev_conn_free(conn);
    }
    output_stdout("all connections are released");

    while (!list_empty(&this->ctx.hdr_dev_list)) {
        dev = list_entry(this->ctx.hdr_dev_list.next, typeof(*dev), list);
        list_del(&dev->list);
        netlev_event_del(this->ctx.epoll_fd, dev->cq_channel->fd,
                         &this->ctx.hdr_event_list);
        netlev_dev_release(dev);
        free(dev);
    }
    output_stdout("all devices are released");

    pthread_mutex_unlock(&this->ctx.lock);

    this->helper.stop = 1;
    pthread_attr_destroy(&this->helper.attr);
    pthread_join(this->helper.thread, &pstatus);

    close(this->ctx.epoll_fd);
    rdma_destroy_event_channel(this->ctx.cm_channel);
}

/* Create a RDMA listener for incoming connection requests */
int 
RdmaServer::create_listener ()
{
    struct sockaddr_in sin;

    this->ctx.cm_channel = rdma_create_event_channel();
    if (!this->ctx.cm_channel) {
        output_stderr("create_event_channel failed");
        goto err_listener;
    }

    if (rdma_create_id(this->ctx.cm_channel, 
                       &this->ctx.cm_id, 
                       NULL, RDMA_PS_TCP)) {
        output_stderr("rdma_create_id failed");
        goto err_listener;
    }

    memset(&sin, 0, sizeof(sin));
    sin.sin_family = AF_INET;
    sin.sin_port = htons(this->data_port);
    sin.sin_addr.s_addr = INADDR_ANY; /* any device */

    if (rdma_bind_addr(this->ctx.cm_id, (struct sockaddr *) &sin)) {
        output_stderr("rdma_bind_addr failed");
        goto err_listener;
    }

    /* 0 == maximum backlog. XXX: not yet bind to any device */
    if (rdma_listen(this->ctx.cm_id, NETLEV_LISTENER_BACKLOG)) {
        output_stderr("rdma_listen failed");
        goto err_listener;
    }

    output_stdout("Server listens on cm_channel=%p",
                  this->ctx.cm_channel);

    /* XXX: add the cm_event channel to the epoll descriptor */
    pthread_mutex_lock(&this->ctx.lock);
    netlev_event_add(this->ctx.epoll_fd, 
                     this->ctx.cm_id->channel->fd, EPOLLIN, 
                     server_cm_handler, this,
                     &this->ctx.hdr_event_list);
    pthread_mutex_unlock(&this->ctx.lock);
    return 0;

err_listener:
    return -1;
}

int 
RdmaServer::destroy_listener()
{
    output_stdout("Closing server fd=%d cm_channel=%p",
                  this->ctx.cm_id->channel->fd, 
                  this->ctx.cm_channel);

    /* Remove the read descriptor from the polling set */
    pthread_mutex_lock(&this->ctx.lock);
    netlev_event_del(this->ctx.epoll_fd, this->ctx.cm_id->channel->fd,
                     &this->ctx.hdr_event_list);

    /* XXX: closing such things from the thread */
    rdma_destroy_id(this->ctx.cm_id);
    rdma_destroy_event_channel(this->ctx.cm_channel);
    pthread_mutex_unlock(&this->ctx.lock);
    return 0;
}

static int 
post_confirmation(const char *params, int length,
                  uint64_t wqeid, void* chunk,
                  netlev_conn_t *conn, struct shuffle_req *req)
{
    netlev_dev_t       *dev;
    netlev_wqe_t       *wqe;
    uint32_t lkey;

    char *tmp_params = const_cast<char*>(params);

    dev = conn->dev;

    pthread_mutex_lock(&dev->lock);
    wqe = get_netlev_wqe(&dev->wqe_list);
    pthread_mutex_unlock(&dev->lock);

    if (wqe) {
        wqe->context = chunk;
        wqe->shreq = req;
        lkey = dev->mem->mr->lkey;
        netlev_post_send(tmp_params, length, wqeid, wqe, conn);
        return 0;
    } else {
        output_stderr("[%s,%d] run out of wqes",__FILE__,__LINE__);
        return -1;
    }
}


int 
RdmaServer::send_msg(const char *buf, int len, uint64_t wqeid, 
                     void *chunk, netlev_conn_t *conn, struct shuffle_req *req)
{
    int ret;
    ret = post_confirmation(buf, len, wqeid, chunk, conn, req);
    return ret > 0;
}

int 
RdmaServer::rdma_write_mof(netlev_conn_t *conn, 
                           uintptr_t laddr,
                           uint64_t req_size, 
                           uint64_t remote_addr, void* chunk)
{
    netlev_dev_t         *dev;
    netlev_wqe_t         *wqe;
    struct ibv_send_wr   *bad_sr;
    int32_t               send_size;
    uint32_t              lkey;

    dev = conn->dev;

    pthread_mutex_lock(&dev->lock);
    wqe = get_netlev_wqe(&dev->wqe_list);
    pthread_mutex_unlock(&dev->lock);

    if (!wqe) {
        output_stderr("[%s,%d] run out of wqes",
                     __FILE__,__LINE__);
        return 0;
    }

    lkey = dev->rdma_mem->mr->lkey;

    send_size = rdma_chunk_len > req_size ? req_size : rdma_chunk_len; 

    init_wqe_rdmaw(wqe, 
                   (int)send_size, 
                   (void *)laddr, 
                   lkey, 
                   (void *)remote_addr,
                   (uint32_t)conn->peerinfo.rdma_mem_rkey);

    wqe->context=chunk;

    if (ibv_post_send(conn->qp_hndl, &(wqe->desc.sr), &bad_sr)) {
        output_stderr("ServerConn: RDMA Post Failed, %s", strerror(errno));
        return 0;
    }    

    return wqe->sge.length;
}

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
