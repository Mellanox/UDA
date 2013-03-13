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
#include "../DataNet/RDMAClient.h"
#include <dlfcn.h>
#include <UdaUtil.h>

#ifndef DC_H
#define DC_H

typedef struct decompressRetData {
	    uint32_t   num_uncompressed_bytes;
	    uint32_t   num_compressed_bytes;
} decompressRetData_t;

class DecompressorWrapper : public InputClient
{

public:

    virtual ~DecompressorWrapper() ;
    DecompressorWrapper (int port, reduce_task_t* reduce_task);

    void start_client();
    void stop_client();
    int start_fetch_req(struct client_part_req *req,  char * buff, int32_t buf_len);
    void comp_fetch_req(struct client_part_req *req);
    RdmaClient* getRdmaClient();

    static void * decompressMainThread(void *arg);  // thread start

    pthread_cond_t		 cond;
    pthread_mutex_t      lock;
    netlev_thread_t      decompress_thread;



protected:

	virtual void initDecompress() = 0;
	void* loadSymbolWrapper(void *handle, const char* symbol);
	InputClient *rdmaClient;

private:

	void *decompressMainThread();
	void handle1Req(client_part_req_t *req);
	bool perliminaryCheck1Req(client_part_req_t *req);
	void doDecompress(client_part_req_t *req);
	void handleNextRdmaFetch(client_part_req_t *req);
	void copy_from_side_buffer_to_actual_buffer(mem_desc_t * dest, uint32_t length);
	virtual uint32_t getBlockSizeOffset() = 0; //For LZO/snappy will return the number of bytes of the block length. for non block alg's will return 0
	virtual void get_next_block_length(char* buf, decompressRetData_t* retObj) = 0; //should be implemented in deriving class since different for block and non block
	virtual  void decompress(const char* compressed_buff, char* uncompressed_buff, size_t compressed_buff_len, size_t uncompressed_buff_len, int offest, decompressRetData_t* retObj)=0;
	bool isRdmaBlockReadyToRead(mem_desc_t *buffer);
	virtual uint32_t getNumCompressedBytes(char* buf)=0;
	virtual uint32_t getNumUncompressedBytes(char* buf)=0;

	list<client_part_req_t *>    req_to_decompress;
	reduce_task_t* 				reduce_task;
	char* buffer; //this is the side buffer to where the data is temporarily decompressed
};

#endif
