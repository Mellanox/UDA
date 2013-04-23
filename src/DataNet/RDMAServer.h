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

#ifndef ROCE_RDMA_SERVER
#define ROCE_RDMA_SERVER	1

#include <list>
#include "RDMAComm.h"

class OutputServer;
class DataEngine;
struct shuffle_req;
struct index_record;
class RdmaServer 
{
public:
	RdmaServer(int port, int rdma_buf_size, void *state);
	~RdmaServer();

	void start_server();
	void stop_server();
	int create_listener ();
	int destroy_listener();
	int rdma_write_mof_send_ack(struct shuffle_req *req, uintptr_t addr,
			uint64_t req_size, void* chunk, struct index_record* record);
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
