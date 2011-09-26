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

#ifndef ROCE_INPUT_CLIENT_H
#define ROCE_INPUT_CLIENT_H      1

#include "../DataNet/RDMAClient.h"

class  RdmaClient;
struct merging_state;

/* A Dummy TcpClient for now */
class TcpClient 
{
public:
    TcpClient(void*, int) {};
    ~TcpClient() {};

    void start() {};

private:
    int                svc_port;	
    netlev_thread_t    helper;
    netlev_ctx_t       ctx;

    int create_client ();
    int destroy_client ();
};

class InputClient 
{
public:
    InputClient() {};
    InputClient(int data_port, int mode, struct merging_state *state);
    ~InputClient();

    void start_client();
    void stop_client();

    /* XXX: the general flow of a fetch request for a client
     * 1. prepare the request 
     * 2. post a request for partition (unknown length) with 
     *    the 1st registered segment 
     * 3. receive the first segment, along with the total length 
     * -- Done if the total length is shorter than the default area
     * -- Otherwise, continue
     * 4. find out the length of the entire partition
     * 5. post the information on the remaining data
     * 6. receive the remaining data 
     * 7. For network levitation, only use the 1st registered segment
     *    to receive more data
     */
    int start_fetch_req(client_part_req_t *req);
    void comp_fetch_req(client_part_req_t *req);

    /* port for data movement between client and server.  */
    int                     data_port;

    pthread_cond_t         *cond;
    RdmaClient             *rdma;
    TcpClient              *tcp;
    struct merging_state   *state; 

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
