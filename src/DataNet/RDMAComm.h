/*
 ** Copyright (C) 2012 Auburn University
 ** Copyright (C) 2012 Mellanox Technologies
 **
 ** Licensed under the Apache License, Version 2.0 (the "License");
 ** you may not use this file except in compliance with the License.
 ** You may obtain a copy of the License at:
 **
 ** http://www.apache.org/licenses/LICENSE-2.0
 **
 ** Unless required by applicable law or agreed to in writing, software
 ** distributed under the License is distributed on an "AS IS" BASIS,
 ** WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
 ** either express or implied. See the License for the specific language
 ** governing permissions and  limitations under the License.
 **
 **
 */

#ifndef  RDMA_COMMON_HEADER 
#define  RDMA_COMMON_HEADER 1

#include <rdma/rdma_cma.h>
#include <stdint.h>

#include "NetlevComm.h"

#define NETLEV_LISTENER_BACKLOG (32)
#define RDMA_DEFAULT_RNR_RETRY  (7)
#define NETLEV_MEM_ACCESS_PERMISSION (IBV_ACCESS_LOCAL_WRITE|IBV_ACCESS_REMOTE_WRITE)

#define SIGNAL_INTERVAL (wqes_perconn/10) //every (signal_interval)th message will be sent with IBV_SEND_SIGNALED
#define CQ_SIZE (64000)

typedef struct connreq_data{
	uint32_t qp;
	uint32_t credits;
	unsigned int rdma_mem_rkey;
} connreq_data_t;

typedef enum {
	MSG_NOOP   = 0x0,
	MSG_RTS    = 0x01,
	MSG_CTS    = 0x02, /* Not used yet. It meant to trigger RDMA Read */
	MSG_INLINE = 0x04,
	MSG_DONE   = 0x08
} msg_type_t;

typedef enum {
	PTR_WQE   = 0x0,
	PTR_CHUNK = 0x01,
} ptr_type_t;

typedef enum {
	RECV_WQE_AVAIL = 0x10, /* Free */
	RECV_WQE_INIT  = 0x11, /* claimed for usage */
	RECV_WQE_POST  = 0x12, /* posted for send/recv data */
	RECV_WQE_COMP  = 0x14, /* data completed */
	RECV_WQE_DONE  = 0x18  /* ready to return into free list */
} recv_wqe_state_t ;

struct netlev_conn;
struct shuffle_req;

typedef struct netlev_msg {
	uint8_t   type;
	uint8_t   credits;  /* credits to the peer */
	uint16_t  padding;
	uint32_t  tot_len;  /* reserved for matching */
	uint64_t  src_req;  /* for fast lookup of request: server will use it to pass pointer to the original request */
	char  msg[NETLEV_FETCH_REQSIZE];
} netlev_msg_t;

typedef struct netlev_wqe {
	uint32_t                type; //!!!!1 must be at offset 0!!!!!! DO NOT MOVE IT!!!!!!
	struct list_head        list;
	union {
		struct ibv_recv_wr   rr;
		struct ibv_send_wr   sr;
	} desc;
	struct ibv_sge           sge;
	struct netlev_conn      *conn;
	char                    *data;
} netlev_wqe_t;

typedef struct netlev_msg_backlog {
	struct list_head        list;
	uint8_t                 type;
	uint32_t                len;
	uint8_t                 padding;
	uint16_t                padding2;
	char                   *msg;
	uint64_t                src_req;
	void                   *context; //save pointer to chunk(server/request(client)
} netlev_msg_backlog_t;


/* device memory for send/receive */
typedef struct netlev_mem {
	struct ibv_mr *mr;
	netlev_wqe_t  *wqe_start;
	void          *wqe_buff_start;
} netlev_mem_t;

/* memory for rdma operation */
typedef struct netlev_rdma_mem {
	struct ibv_mr       *mr;
	uint64_t       total_size;
} netlev_rdma_mem_t;


typedef struct netlev_dev {
	struct ibv_context       *ibv_ctx;
	struct ibv_pd            *pd;
	struct ibv_cq            *cq;
	struct ibv_comp_channel  *cq_channel;
	netlev_rdma_mem_t        *rdma_mem;

	struct list_head          list;     /* for device list*/
	uint32_t                  cqe_num;
	uint32_t                  max_sge;
} netlev_dev_t;

typedef enum {
	NETLEV_CONN_INIT  = 0x0,
	NETLEV_CONN_RTR   = 0x1,
	NETLEV_CONN_RTS   = 0x2,
	NETLEV_CONN_READY = 0x4,
} conn_state_t;

typedef struct netlev_conn
{
	struct netlev_dev  *dev;
	struct rdma_cm_id  *cm_id;
	struct ibv_qp      *qp_hndl;

	struct list_head    backlog;
	struct list_head    list;

	uint32_t            credits;   /* remaining credits */
	uint32_t            returning; /* returning credits */

	pthread_mutex_t     lock;
	connreq_data_t      peerinfo;
	netlev_mem_t        *mem;
	unsigned long       peerIPAddr;
	unsigned int        state;
	uint32_t			sent_counter;
	bool				bad_conn;
	uint32_t			received_counter; //used by server to track requests received from this connection
} netlev_conn_t;

int netlev_dealloc_mem(struct netlev_dev *dev, netlev_mem_t *mem);
int netlev_dealloc_rdma_mem(struct netlev_dev *dev);
int netlev_init_mem(struct netlev_dev *dev);
int netlev_dev_init(struct netlev_dev *dev);
int netlev_dev_release(struct netlev_dev *dev);

struct netlev_dev *netlev_dev_find(struct rdma_cm_id *cm_id, struct list_head *head);

struct netlev_conn *netlev_conn_find_by_ip(unsigned long ipaddr, struct list_head *head);
struct netlev_conn * netlev_conn_find_by_qp(uint32_t qp_num, struct list_head *head);

void netlev_conn_free(netlev_conn_t *conn);

struct netlev_conn *netlev_conn_alloc(struct netlev_dev *dev, struct rdma_cm_id *cm_id);

void init_wqe_rdmaw(struct ibv_send_wr *send_wr, struct ibv_sge *sg, int len,
		void *laddr, uint32_t lkey,
		void *raddr, uint32_t rkey, struct ibv_send_wr *next_wr);

void init_wqe_send(ibv_send_wr *send_wr,ibv_sge *sg, netlev_msg_t *h, unsigned int len,
		bool send_signal, void* context);
void init_wqe_recv(netlev_wqe_t *wqe, unsigned int len,
		uint32_t lkey, netlev_conn_t *conn);

//netlev_wqe_t * get_netlev_wqe (struct list_head *head); LCOV_AUBURN_DEAD_CODE

void set_wqe_addr_key(netlev_wqe_t * wqe, 
		int len,
		void *local_addr,
		uint32_t lkey,
		void *remote_addr,
		uint32_t rkey);

typedef struct netlev_ctx {
	struct list_head           hdr_event_list;
	struct list_head           hdr_dev_list;
	struct list_head           hdr_conn_list;
	int                        epoll_fd;
	pthread_mutex_t            lock;

	struct rdma_event_channel *cm_channel;
	struct rdma_cm_id         *cm_id;
} netlev_ctx_t;

/* return a completion channel, and a QP */
struct netlev_conn *netlev_init_conn(struct rdma_cm_event *event, struct netlev_dev *dev);

struct netlev_conn *netlev_conn_established(struct rdma_cm_event *event, struct list_head *head);

void netlev_disconnect(struct netlev_conn *conn);

netlev_msg_backlog_t *init_backlog_data(uint8_t type, uint32_t len, uint64_t src_req, void *context, char *msg );

struct netlev_conn *netlev_disconnect(struct rdma_cm_event *ev, struct list_head *head);

int netlev_post_send(netlev_msg_t *h, int bytes,
		uint64_t srcreq, void* context,
		netlev_conn_t *conn, uint8_t msg_type);

int netlev_init_rdma_mem(void *, unsigned long total_size, netlev_dev_t *dev);

const char* netlev_stropcode(int opcode);

#endif
