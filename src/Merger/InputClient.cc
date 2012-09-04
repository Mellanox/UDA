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

#include <dirent.h>
#include <unistd.h>
#include <fcntl.h>

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
	MergeManager *merge_man = req->mop->task->merge_man;
	merge_man->update_fetch_req(req);
}

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
