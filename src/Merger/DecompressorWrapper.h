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

class DecompressorWrapper : public InputClient
{
public:
    virtual ~DecompressorWrapper() ;

    DecompressorWrapper (int port, reduce_task_t* reduce_task);

    virtual void decompress(char* compressed, int length) = 0;
    virtual void initDecompress() = 0;
    bool load(char *library_name); //- implemented in the abstract class . STATIC>?????. in java it is  System.loadLibrary("gplcompression");
    char* getParamFromJava(char* property_name);// - implemented in the abstract class. if it is int: to convert it in the calling function?
    virtual int get_next_block_length(char* buff) = 0; //should be implemented in deriving class since different for block and non block

    void start_client();
    void stop_client();

    int start_fetch_req(struct client_part_req *req);
    void comp_fetch_req(struct client_part_req *req);
    RdmaClient* getRdmaClient();
    virtual int getBlockSizeOffset() = 0; //For LZO will return the number of bytes of the block length. for non block alg's will return 0

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

};


/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
