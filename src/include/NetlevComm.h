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

#ifndef NETLEV_COMM_H
#define NETLEV_COMM_H

#include "LinkList.h"

#define NETLEV 1

#define NETLEV_TIMEOUT_MS        (5000)
#define NETLEV_MAX_HOSTS         (64)
#define NETLEV_FETCH_REQSIZE     (128)
#define NETLEV_WQES_PERCONN      (128)
#define NETLEV_WQES_SEND_PERCONN (NETLEV_WQES_PERCONN/2)
#define NETLEV_WQES_RECV_PERCONN (NETLEV_WQES_PERCONN/2)

#define NETLEV_KV_POOL_EXPO         (20)

#define NETLEV_MAX_MOFS_INCACHE     (8192)
#define NETLEV_RDMA_MEM_CHUNKS_NUM	(1000)

#define ARRAY_SIZE(array) (sizeof array / sizeof array[0])
#define RDMA_TIMEOUT 2

#define long2ptr(p) (void *)(unsigned long)(p)
#define ptr2long(p) (u_int64_t)(unsigned long)(p)

enum {
    DBG_CLIENT = 0x1,
    DBG_SERVER = 0x2,
    DBG_CONN   = 0x4,
};

extern int netlev_dbg_flag;

struct progress_event;
typedef void (*event_handler_t) (struct progress_event *pevent, void *ctx);

typedef struct progress_event {
    int                 fd;
    struct list_head    list;
    event_handler_t     handler;
    void               *data;
} progress_event_t;


typedef struct {
    pthread_t        thread;
    pthread_attr_t   attr;
    volatile int     stop;
    int	             pollfd;
    void            *context;
} netlev_thread_t;

void dprint(char *s, char *fmt, ...);

#define  DBGPRINT(flag, args...)     \
    do {                                 \
       	if (netlev_dbg_flag & (flag)) {  \
            char s0[32];                 \
            sprintf(s0, "[%d:%d:%s] ", getpid(), __LINE__, __FILE__); \
            dprint(s0, args);            \
       	}                                \
    } while (0)


int netlev_event_add(int poll_fd, int fd, int events, 
                     event_handler_t handler, void *data, 
	                 struct list_head *head);

void netlev_event_del(int poll_fd, int fd, struct list_head *head);

void *event_processor(void *context);

#endif

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
