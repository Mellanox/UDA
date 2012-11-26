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

#ifndef ROCE_RDMA_CLIENT	
#define ROCE_RDMA_CLIENT	1

#include <map>
#include "RDMAComm.h"
#include "../Merger/reducer.h"
#include "../Merger/InputClient.h"


class RdmaClient : public InputClient
{
public:
    RdmaClient (int port, reduce_task_t* reduce_task);
    ~RdmaClient();

    netlev_conn_t* connect(const char *host, int port);
//    void disconnect(netlev_conn_t *conn); //LCOV_AUBURN_DEAD_CODE
    void register_mem(struct memory_pool *mem_pool);
    unsigned long get_hostip(const char *host);

    void start_client();
    void stop_client();

    int start_fetch_req(client_part_req_t *req);
    void comp_fetch_req(client_part_req_t *req);

    RdmaClient* getRdmaClient();

    int                 svc_port;
    netlev_thread_t     helper;
    netlev_ctx_t        ctx;
    InputClient        *parent;
//    merging_state_t    *state;
    reduce_task_t* reduce_task;
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
