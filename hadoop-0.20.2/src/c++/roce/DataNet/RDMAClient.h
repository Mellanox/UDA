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

#ifndef ROCE_RDMA_CLIENT	
#define ROCE_RDMA_CLIENT	1

#include <map>
#include "RDMAComm.h"
#include "../Merger/reducer.h"

class RdmaClient
{
public:
    RdmaClient (int port, merging_state_t *state);
    ~RdmaClient();

    netlev_conn_t* connect(const char *host, int port);
    void disconnect(netlev_conn_t *conn);
    void register_mem(struct memory_pool *mem_pool);
    int fetch(client_part_req_t *freq);
    int fetch_over(client_part_req_t *freq);
    unsigned long get_hostip(const char *host);

    int                 svc_port;
    netlev_thread_t     helper;
    netlev_ctx_t        ctx;
    InputClient        *parent;
    merging_state_t    *state;
    struct list_head    wait_reqs;
    struct list_head    register_mems_head;
    std::map<std::string, unsigned long> local_dns;
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
