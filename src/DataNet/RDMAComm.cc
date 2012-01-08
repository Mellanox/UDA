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
#include <sys/ioctl.h>
#include <malloc.h>
#include <netdb.h>
#include <errno.h>
#include <stdarg.h>

#include <infiniband/verbs.h>
#include <rdma/rdma_cma.h>

#include "RDMAComm.h"
#include "IOUtility.h"


int rdma_debug_flag = 0x0;

int 
netlev_dealloc_dev_mem(struct netlev_dev *dev, netlev_mem_t *mem)
{
    while(!list_empty(&dev->wqe_list)) {
        netlev_wqe_t *wqe;
        wqe = list_entry(dev->wqe_list.next, typeof(*wqe), list);
        list_del(&wqe->list);
    }

    ibv_dereg_mr(mem->mr);
    free(mem->wqe_start);
    free(mem->wqe_buff_start);
    free(mem);
    return 0;
}

int
netlev_dealloc_rdma_mem(struct netlev_dev *dev)
{
    ibv_dereg_mr(dev->rdma_mem->mr);
    free(dev->rdma_mem);
    return 0;
}

int
netlev_init_rdma_mem(void *mem, uint64_t total_size,
                     netlev_dev_t *dev)
{
    netlev_rdma_mem_t *rdma_mem;

    rdma_mem = (netlev_rdma_mem_t *) malloc(sizeof(netlev_rdma_mem_t));
    if (!rdma_mem) {
        output_stderr("[%s,%d] malloc struct netlev_rdma_mem failed",
                      __FILE__,__LINE__);
        return -1;
    }

    rdma_mem->total_size = total_size;
    rdma_mem->mr = ibv_reg_mr(dev->pd, mem, total_size, NETLEV_MEM_ACCESS_PERMISSION);
    if (!rdma_mem->mr) {
        log(lsERROR,"register rdma memory region. total_size=%llu  , MSG=%m", total_size);
        free(rdma_mem);
        return -1;
    }

    dev->rdma_mem = rdma_mem;
    return 0;
}

int
netlev_init_dev_mem(struct netlev_dev *dev)
{
    netlev_mem_t *dev_mem;
    void         *wqe_mem;
    void         *dma_mem;

    int wqe_align = 64;
    int num_wqes  = wqes_perconn  * max_hosts;
    int data_size = NETLEV_FETCH_REQSIZE * num_wqes;
    int dma_align = getpagesize();

    log(lsDEBUG, "IDAN - wqes_perconn=%d max_hosts=%d", wqes_perconn  , max_hosts);

    /* alloc dev_mem struct */
    dev_mem = (netlev_mem_t *) malloc(sizeof(netlev_mem_t));
    if (!dev_mem) {
        output_stderr("[%s,%d] malloc netlev_mem_t failed",
                      __FILE__,__LINE__);
        goto error_dev;
    }
    memset(dev_mem, 0, sizeof(struct netlev_mem));

    /* alloc wqes */
    wqe_mem = memalign(wqe_align, num_wqes * sizeof(netlev_wqe_t));
    if (!wqe_mem) {
        output_stderr("[%s,%d] malloc netlev_wqe_t failed",
                     __FILE__,__LINE__);
        goto error_wqe;
    }
    memset(wqe_mem, 0, num_wqes * sizeof (netlev_wqe_t));

    /* alloc memory buffer for wqes */
    dma_mem = memalign(dma_align, data_size);
    if (!dma_mem) {
        output_stderr("[%s,%d] malloc data buffer failed",
                     __FILE__,__LINE__);
        goto error_dma;
    }
    memset(dma_mem, 0, data_size);

    dev_mem->count = num_wqes;
    dev_mem->wqe_start = (netlev_wqe_t *)wqe_mem;
    dev_mem->wqe_buff_start = dma_mem;
    dev_mem->mr = ibv_reg_mr(dev->pd, dma_mem, data_size, NETLEV_MEM_ACCESS_PERMISSION);
    if (!dev_mem->mr) {
        output_stderr("[%s,%d] register mem failed",
                     __FILE__,__LINE__);
        goto error_register;
    }

    /* init the free wqe list */
    for (int i = 0; i < num_wqes; i++) {
        netlev_wqe_t *cur = dev_mem->wqe_start + i;
        cur->data = (char *)(dma_mem) + (i * NETLEV_FETCH_REQSIZE);
        list_add_tail(&cur->list, &dev->wqe_list);
    }
    dev->mem = dev_mem;
    return 0;

error_register:
    free(dma_mem);
error_dma:
    free(wqe_mem);
error_wqe:
    free(dev_mem);
error_dev:
    return -1;
}

void 
netlev_dev_release(struct netlev_dev *dev)
{
    ibv_destroy_cq(dev->cq);
    ibv_destroy_comp_channel(dev->cq_channel);
    netlev_dealloc_dev_mem(dev, dev->mem);
    netlev_dealloc_rdma_mem(dev);
    ibv_dealloc_pd(dev->pd);
    pthread_mutex_destroy(&dev->lock);
}

int 
netlev_dev_init(struct netlev_dev *dev)
{
    struct ibv_device_attr device_attr;
    int cqe_num, max_sge;

    INIT_LIST_HEAD(&dev->wqe_list);
    pthread_mutex_init(&dev->lock, NULL);
    memset(&device_attr, 0, sizeof(struct ibv_device_attr));

    dev->pd = ibv_alloc_pd(dev->ibv_ctx);
    if (!dev->pd) {
        output_stderr("[%s,%d] ibv_alloc_pd failed",
                      __FILE__,__LINE__);
        return -1;
    }

    if (netlev_init_dev_mem(dev) != 0) {
        return -1;
    }

    if (ibv_query_device(dev->ibv_ctx, &device_attr) != 0) {
        output_stderr("[%s,%d] ibv_query_device",
                     __FILE__,__LINE__);
        return -1;
    }

//    cqe_num = device_attr.max_cqe;
    cqe_num = wqes_perconn  * max_hosts;
    max_sge = device_attr.max_sge;

    dev->cq_channel = ibv_create_comp_channel(dev->ibv_ctx);
    if (!dev->cq_channel) {
        output_stderr("[%s,%d] ibv_create_comp_channel failed",
                      __FILE__,__LINE__);
        return -1;
    }

    dev->cq = ibv_create_cq(dev->ibv_ctx, cqe_num, NULL, dev->cq_channel, 0);
    if (!dev->cq) {
        output_stderr("[%s,%d] ibv_create_cq failed",
                      __FILE__,__LINE__);
        return -1;
    }
    log (lsDEBUG, "device_attr.max_cqe is %d, cqe_num is %d, actual cqe is %d", device_attr.max_cqe, cqe_num, dev->cq->cqe );

    if (ibv_req_notify_cq(dev->cq, 0) != 0) {
        output_stderr("[%s,%d] ibv_req_notify failed",
                     __FILE__,__LINE__);
        return -1;
    }

    dev->max_sge = max_sge;
    dev->cqe_num = cqe_num;
    return 0;
}
 
struct netlev_dev* 
netlev_dev_find(struct rdma_cm_id *cm_id, list_head_t *head)
{
    struct netlev_dev *dev = NULL;
    
    list_for_each_entry(dev, head, list) {
        if (dev->ibv_ctx == cm_id->verbs) {
            return dev;
        }
    }
    return NULL;
}

void 
netlev_conn_free(netlev_conn_t *conn)
{
    netlev_wqe_t *wqe;
    /* free wqes */
    pthread_mutex_lock(&conn->lock);
    while (!list_empty(&conn->backlog)) {
        wqe = list_entry(conn->backlog.next, typeof(*wqe), list);
        list_del(&wqe->list);
        release_netlev_wqe(wqe, &conn->dev->wqe_list);
    }
    pthread_mutex_unlock(&conn->lock);

    rdma_destroy_qp(conn->cm_id);
    rdma_destroy_id(conn->cm_id);
    pthread_mutex_destroy(&conn->lock);
    list_del(&conn->list);
    free(conn);
};

struct netlev_conn *
netlev_conn_alloc(netlev_dev_t *dev, struct rdma_cm_id *cm_id) 
{
    /* build a new connection structure */
    netlev_conn_t *conn;
    struct ibv_recv_wr *bad_wr;
    struct ibv_qp_init_attr qp_init_attr;
    int wqes_recv_perconn = wqes_perconn/2;

    conn = (netlev_conn_t*) calloc(1, sizeof(netlev_conn_t));
    if (!conn) {
        output_stderr("[%s,%d] allocate conn failed",
                      __FILE__,__LINE__);
        return NULL;
    }

    conn->cm_id = cm_id;
    conn->dev = dev;

    pthread_mutex_init(&conn->lock, NULL);
    INIT_LIST_HEAD(&conn->backlog); /* backlog of wqes */
    INIT_LIST_HEAD(&conn->list);

    memset(&qp_init_attr, 0, sizeof(qp_init_attr));
    qp_init_attr.send_cq  = dev->cq;
    qp_init_attr.recv_cq  = dev->cq;
    qp_init_attr.cap.max_send_wr  = wqes_recv_perconn;
    qp_init_attr.cap.max_recv_wr  = wqes_recv_perconn;
    qp_init_attr.cap.max_send_sge = 16; /* 28 is the limit */  
    qp_init_attr.cap.max_recv_sge = 16; /* 28 is the limit */
    qp_init_attr.qp_type = IBV_QPT_RC;
    qp_init_attr.sq_sig_all = 0;

    if (qp_init_attr.cap.max_recv_sge > dev->max_sge) {
        qp_init_attr.cap.max_recv_sge = dev->max_sge;
        qp_init_attr.cap.max_send_sge = dev->max_sge - 1;
    }

    if (rdma_create_qp(conn->cm_id, dev->pd, &qp_init_attr) != 0) {
        output_stderr("[%s,%d] Create qp failed - %m",
                     __FILE__,__LINE__);
        free(conn);
        return NULL;
    }
    conn->qp_hndl = conn->cm_id->qp;
    memset(&conn->peerinfo, 0, sizeof(connreq_data_t));
    log(lsDEBUG, "allocating %d wqes to be receving wqes", wqes_recv_perconn);
    /* post as many recv wqes as possible, up to wqes_perconn/2 */
    for (int i = 0; i < wqes_recv_perconn; ++i) {
        netlev_wqe_t *wqe = get_netlev_wqe(&dev->wqe_list);
        if (!wqe) {
           output_stderr("[%s,%d] no more wqe for receiving",
                        __FILE__,__LINE__);
           if (i == 0) {
               netlev_conn_free(conn);
               return NULL;
           } 
           break;
        }
        init_wqe_recv(wqe, NETLEV_FETCH_REQSIZE, dev->mem->mr->lkey, conn);
        if (ibv_post_recv(conn->qp_hndl, &wqe->desc.rr, &bad_wr) != 0) {
            output_stderr("[%s,%d] ibv_post_recv",
                          __FILE__,__LINE__);
            netlev_conn_free(conn);
            return NULL;
        }
    }
    return conn;
};

struct netlev_conn* 
netlev_find_conn_by_qp (uint32_t qp_num, struct list_head *q)
{
    struct netlev_conn *conn = NULL;
    list_for_each_entry(conn, q, list) {
        if (conn->qp_hndl->qp_num == qp_num) {
            return conn;
        }
    }
    return NULL;
}

struct netlev_conn* 
netlev_find_conn_by_ip (unsigned long ipaddr, struct list_head *q)
{
    struct netlev_conn *conn = NULL;
    list_for_each_entry(conn, q, list) {
        if (conn->peerIPAddr == ipaddr) {
            return conn;
        }
    }
    return NULL;
}

void 
dprint(char *s, char *fmt, ...)
{
    char s1[256];
    va_list ap;
    va_start(ap, fmt);
    vsprintf(s1, fmt, ap);
    va_end(ap);
    fprintf(stderr, "%s %s", s, s1);
}


void 
init_wqe_send (netlev_wqe_t *wqe, unsigned int len, 
               uint32_t lkey, netlev_conn_t *conn)
{
    wqe->desc.sr.next       = NULL;
    wqe->desc.sr.send_flags = IBV_SEND_SIGNALED;
    wqe->desc.sr.opcode     = IBV_WR_SEND;
    wqe->desc.sr.wr_id      = (uintptr_t) wqe;
    wqe->desc.sr.num_sge    = 1;
    wqe->desc.sr.sg_list    = &(wqe->sge);
    wqe->sge.length         = len;
    wqe->sge.lkey           = lkey;
    wqe->sge.addr           = (uintptr_t)(wqe->data);
    wqe->conn               = conn;
    wqe->state              = SEND_WQE_INIT;
}

void 
init_wqe_recv (netlev_wqe_t *wqe, unsigned int len, 
               uint32_t lkey, netlev_conn_t *conn)
{
    wqe->desc.rr.next   = NULL;
    wqe->desc.rr.wr_id  = (uintptr_t) wqe;
    wqe->desc.rr.num_sge= 1;
    wqe->desc.rr.sg_list= &(wqe->sge);
    wqe->sge.length     = len;
    wqe->sge.lkey       = lkey;
    wqe->sge.addr       = (uintptr_t)(wqe->data);
    wqe->conn           = conn;
    wqe->state          = RECV_WQE_INIT;
}

netlev_wqe_t* 
get_netlev_wqe (struct list_head *head)
{
    netlev_wqe_t *wqe = NULL;

    if (list_empty(head)) return NULL;
        
    wqe = list_entry(head->next, typeof(*wqe), list);
    list_del(&wqe->list);
    return (wqe);
}

void 
release_netlev_wqe (netlev_wqe_t *wqe, struct list_head *head)
{
    list_add_tail(&wqe->list, head);
    wqe->state &= SEND_WQE_AVAIL;
}

void 
init_wqe_rdmaw(netlev_wqe_t *wqe, int len,
               void *laddr, uint32_t lkey,
               void *raddr, uint32_t rkey)
{
    wqe->desc.sr.next       = NULL;
    wqe->desc.sr.opcode     = IBV_WR_RDMA_WRITE;
    wqe->desc.sr.send_flags = IBV_SEND_SIGNALED;
    wqe->desc.sr.wr_id      = (uintptr_t) wqe;
    wqe->desc.sr.num_sge    = 1;
    wqe->desc.sr.sg_list    = &(wqe->sge);
    wqe->state              = SEND_WQE_INIT;
    wqe->sge.length         = (len);
    wqe->sge.lkey           = (lkey);
    wqe->sge.addr           = (uintptr_t)(laddr);
    wqe->desc.sr.wr.rdma.rkey = (rkey);
    wqe->desc.sr.wr.rdma.remote_addr = (uintptr_t) (raddr);
}

int 
netlev_event_add(int poll_fd, int fd, int events, 
                 event_handler_t handler, void *data, 
                 struct list_head *head)
{
    progress_event_t *pevent;
    struct epoll_event ev;
    int err;

    memset(&ev, 0, sizeof(struct epoll_event));
    pevent = (progress_event_t *) calloc(1, sizeof(progress_event_t));
    pevent->fd = fd;
    pevent->data = data;
    pevent->handler = handler;

    ev.events = events;
    ev.data.fd = fd;
    ev.data.ptr = pevent;
    err = epoll_ctl(poll_fd, EPOLL_CTL_ADD, fd, &ev);
    if (err) {
        output_stderr("[%s,%d] cannot add fd",
                     __FILE__,__LINE__);
        return err;
    }

    list_add_tail(&pevent->list, head);
    return err;
}

void 
netlev_event_del(int poll_fd, int fd, struct list_head *head)
{
    progress_event_t *pevent;

    list_for_each_entry(pevent, head, list) {
        if (pevent->fd == fd) {
            epoll_ctl(poll_fd, EPOLL_CTL_DEL, fd, NULL);
            list_del(&pevent->list);
            free(pevent);
            return;
        }
    }
    
    output_stderr("[%s,%d] Event fd %d not found",
                 __FILE__,__LINE__,fd);
}

struct netlev_conn*
netlev_init_conn(struct rdma_cm_event *event,
                 struct netlev_dev *dev)
{
    struct netlev_conn *conn = NULL;
    struct rdma_conn_param conn_param;
    struct connreq_data xdata;

    conn = netlev_conn_alloc(dev, event->id);
    if (!conn) {
        goto err_alloc_dev;
    }

    /* Save an extra one for credit flow */
    memset(&xdata, 0, sizeof(xdata));
    xdata.qp = conn->qp_hndl->qp_num;
    xdata.credits = wqes_perconn/2 - 1;
    xdata.mem_rkey = dev->mem->mr->rkey;
    xdata.rdma_mem_rkey = dev->rdma_mem->mr->rkey;

    memset(&conn_param, 0, sizeof(conn_param));
    conn_param.responder_resources = 1;
    conn_param.initiator_depth = 1;
    conn_param.retry_count = RDMA_DEFAULT_RNR_RETRY;
    conn_param.rnr_retry_count = RDMA_DEFAULT_RNR_RETRY;
    conn_param.private_data = &xdata;
    conn_param.private_data_len = sizeof(xdata);

    /* accept the connection */
    if (rdma_accept(conn->cm_id, &conn_param) != 0) {
        output_stderr("[%s,%d] rdma_accept failed",
                      __FILE__,__LINE__);
        goto err_rdma_conn;
    }
    return conn;

err_rdma_conn:
    netlev_conn_free(conn);
err_alloc_dev:
    if (rdma_reject(event->id, NULL, 0) != 0) {
        output_stderr("[%s,%d] rdma_reject failed",
                      __FILE__,__LINE__);
    }
    return NULL;
}


struct netlev_conn*
netlev_conn_established(struct rdma_cm_event *event,
                        struct list_head *head)
{
    int found = 0;
    struct netlev_conn *conn;

    list_for_each_entry(conn, head, list) {
        if (conn->cm_id == event->id) {
            found = 1;
            break;
        }
    }

    if (!found) {
        output_stderr("event=%p id=%p qp_num=%d not found", 
                      event, event->id, event->id->qp->qp_num);
        return NULL;
    } else {
        conn->state = NETLEV_CONN_READY;
        output_stdout("A connection is fully ready conn=%p", conn);
        return conn;
    }
}

struct netlev_conn*
netlev_disconnect(struct rdma_cm_event *ev, 
                  struct list_head *head)
{
    struct netlev_conn *conn;

    list_for_each_entry(conn, head, list) {
        if (conn->qp_hndl->qp_num == ev->id->qp->qp_num) {
            rdma_disconnect(ev->id);
            netlev_conn_free(conn);
            return conn;
        }
    }
    return NULL;
}

int
netlev_send_noop(struct netlev_conn *conn)
{
    struct ibv_send_wr *bad_wr;
    netlev_wqe_t       *wqe;
    hdr_header_t       *h;
    netlev_dev_t       *dev;
    dev =conn->dev;
    pthread_mutex_lock(&dev->lock);
    wqe = get_netlev_wqe(&dev->wqe_list);
    pthread_mutex_unlock(&dev->lock);
    if (!wqe) {
    	log(lsERROR,"no more wqes");
    	return false;
    }

    h = (hdr_header_t*) wqe->data;
    h->type = MSG_NOOP;
    h->tot_len = 0;
    h->credits = 0;
    h->src_req = 0;

    init_wqe_send (wqe, sizeof(hdr_header_t), dev->mem->mr->lkey, conn);

    pthread_mutex_lock(&conn->lock);
    if (conn->returning) {
        h->credits = conn->returning;
        conn->returning = 0;
        conn->credits--;
        if (ibv_post_send(conn->qp_hndl, &(wqe->desc.sr), &bad_wr) != 0) {
            output_stderr("[%s,%d] Error posting send",
                          __FILE__,__LINE__);
            pthread_mutex_unlock(&conn->lock);
            return -1;
        }
    }
    pthread_mutex_unlock(&conn->lock);
    return 0;
}


int 
netlev_post_send(void *buff, int bytes, 
                 uint64_t srcreq,
                 netlev_wqe_t *wqe, 
                 netlev_conn_t *conn)
{
	int rc;
    int len;
    struct ibv_send_wr *bad_wr;
    uint32_t lkey = conn->dev->mem->mr->lkey;
    hdr_header_t *h;

    h = (hdr_header_t *) wqe->data;
    h->type = MSG_RTS;
    h->tot_len = bytes;
    h->credits = 0;
    h->src_req = srcreq ? srcreq : 0;

    len = sizeof(*h) + bytes;
    if (len <= NETLEV_FETCH_REQSIZE) {
        memcpy (((char *) h + sizeof (*h)), buff, bytes);
    } else {
        output_stderr("[%s,%d] request too long",
                      __FILE__,__LINE__);
        return -1;
    }
    init_wqe_send(wqe, (unsigned long) len, lkey, conn);
    /* XXX: if there is credits, send it 
     * Otherwise, put it in the backlog */
    pthread_mutex_lock(&conn->lock);
    if (conn->credits > 0) {
        conn->credits --;
        
        if (conn->returning) {
            h->credits = conn->returning;
            conn->returning = 0;
        } 
        log(lsTRACE, "message before ibv_post_send is %s", (char*) buff);
//        log(lsTRACE, "there are %d credits in connection_qp.num=%d", conn->credits, conn->qp_hndl->qp_num);
        log(lsTRACE, "ibv_post_send: %s", (char*)buff);
        if ((rc = ibv_post_send(conn->qp_hndl, &(wqe->desc.sr), &bad_wr)) != 0) {
            log(lsERROR, "ibv_post_send error: errno=%d %m", rc, (char*)buff);
            pthread_mutex_unlock(&conn->lock);
            return -1;
        }
        wqe->state = SEND_WQE_POST;
    } else {
    	log(lsDEBUG, "no credit to post send. add to backlog: %s", (char*)buff);
        list_add_tail(&wqe->list, &conn->backlog);
        pthread_mutex_unlock(&conn->lock);
        return -2;
    }
    pthread_mutex_unlock(&conn->lock);
    return 0;
}

const char* netlev_stropcode(int opcode)
{
    switch (opcode) {
        case IBV_WC_SEND:
            return "IBV_WC_SEND";    
            break;

        case IBV_WC_RECV:
            return "IBV_WC_RECV";
            break;

    }
    return "NULL";
}

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
