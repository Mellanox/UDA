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

typedef struct decompressRetData {
	    uint32_t   num_uncompressed_bytes;
	    uint32_t   num_compressed_bytes;
} decompressRetData_t;

class DecompressorWrapper : public InputClient
{
public:
    virtual ~DecompressorWrapper() ;

    DecompressorWrapper (int port, reduce_task_t* reduce_task);

    virtual decompressRetData_t* decompress(char* compressed_buff, char* uncompressed_buff, size_t compressed_buff_len, size_t uncompressed_buff_len,int offest)=0;
    virtual void initDecompress() = 0;
    virtual void get_next_block_length(char* buf, decompressRetData_t* retObj) = 0; //should be implemented in deriving class since different for block and non block
    void start_client();
    void stop_client();

    int start_fetch_req(struct client_part_req *req,  char * buff, int32_t buf_len);
    void comp_fetch_req(struct client_part_req *req);
    RdmaClient* getRdmaClient();
    virtual uint32_t getBlockSizeOffset() = 0; //For LZO will return the number of bytes of the block length. for non block alg's will return 0
    void initJniEnv();
    void* loadSymbol(void *handle, const char* symbol);

    bool library_loaded;
    char* library_name; //to be passed in the c-tor?
    InputClient *rdmaClient;
    int port;
//    merging_state_t    *state;
    reduce_task_t* reduce_task;
    pthread_cond_t cond;
    pthread_mutex_t      lock;
    list<client_part_req_t *>    req_to_decompress;
    netlev_thread_t    decompress_thread;
    char* buffer; //this is the side buffer to where the data is decompressed
    JNIEnv *jniEnv;
};
