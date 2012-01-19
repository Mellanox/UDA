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

#include <dirent.h>
#include <unistd.h>
#include <fcntl.h>

#include "FetchManager.h"
#include "InputClient.h"

using namespace std;

InputClient::InputClient(int data_port, int mode, merging_state_t *state)
{
    this->data_port = data_port;
    this->rdma  = NULL; 
    this->tcp   = NULL;
    this->state = state;
}

InputClient::~InputClient()
{
    this->rdma  = NULL; 
    this->tcp   = NULL;
    this->state = NULL;
    this->data_port = -1;
}


void InputClient::start_client()
{
    this->rdma = new RdmaClient(this->data_port, this->state);
}

void InputClient::stop_client()
{
    delete this->rdma;
    this->rdma = NULL;
}

int InputClient::start_fetch_req(client_part_req_t *req)
{
   return this->rdma->fetch(req); 
}

void InputClient::comp_fetch_req(client_part_req_t *req)
{
    FetchManager *fetch_man = req->mop->task->fetch_man;
    fetch_man->update_fetch_req(req);
}

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
