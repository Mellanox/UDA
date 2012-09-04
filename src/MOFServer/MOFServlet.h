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

#ifndef ROCE_MOF_SERVER_H
#define ROCE_MOF_SERVER_H      1

#include <string>
#include <map>

#include "C2JNexus.h"
#include "IndexInfo.h"
#include "../DataNet/RDMAServer.h"

/* A Dummy TcpServer for now */
class TcpServer 
{
public:
    TcpServer(void*, int) {};
    ~TcpServer() {};

    void start() {};
private:
    int                svc_port;	
    netlev_thread_t    helper;
    netlev_ctx_t       ctx;

    int create_listener ();
    int destroy_listener();
};

shuffle_req_t * get_shuffle_req(const string &param);

class OutputServer 
{
public:
    OutputServer() {};
    OutputServer(int data_port, int mode, int rdma_buf_size,
                 supplier_state_t *state);

    ~OutputServer();

    void start_server();
    void stop_server();

    /* XXX: the general flow of a fetch request  
     * 1. insert a fetch request, 
     * 2. read from disk, 
     * 3. RDMA write data via netlev_write_data()
     * 4. Send a confirmation
     * 5. Complete the outgoing request
     */
    void insert_incoming_req(shuffle_req_t *req);
    void start_outgoing_req(shuffle_req_t *req, index_record_t* record,  chunk_t* chunk, uint64_t length, int offsetAligment);

    /* port for data movement between client and server.  */
    int               data_port;
    int               rdma_buf_size; //size of a single rdma buffer.
    RdmaServer       *rdma;
    TcpServer        *tcp;
    supplier_state_t *state; /* data engine */

    pthread_mutex_t   in_lock;
    pthread_mutex_t   out_lock;
    pthread_cond_t    in_cond;
    struct list_head  incoming_req_list;

    /**
     * Under standalone mode, list all the valid fetch request 
     * according to the test intermediate map output files under
     * MOF directory
     */
    void list_fet_req(const char *test_dir);

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
