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

#ifndef ROCE_RDMA_SERVER
#define ROCE_RDMA_SERVER	1

#include <list>
#include "RDMAComm.h"

class OutputServer;
class DataEngine;
struct shuffle_req;

class RdmaServer 
{
public:
    RdmaServer(int port, void *state); 
    ~RdmaServer();

    void start_server();
    void stop_server();
    int create_listener ();
    int destroy_listener();
    int rdma_write_mof(netlev_conn_t *conn, uintptr_t addr, 
                       uint64_t req_size, uint64_t remote_addr);

    int send_msg(const char *, int len, 
                 uint64_t wqeid, void* chunk, 
                 netlev_conn_t *conn, struct shuffle_req*);

    int                data_port;	
    void              *rdma_mem;
    unsigned long      rdma_total_len;
    uint32_t           rdma_chunk_len;
    netlev_thread_t    helper;
    netlev_ctx_t       ctx;
    OutputServer      *parent;
    DataEngine        *data_mac;
  
};

#endif

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
