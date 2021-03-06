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

#ifndef NETLEV_REDUCER_H
#define NETLEV_REDUCER_H      1

#include <list>
#include <string>
#include <map>
#include <set>
#include <vector>
#include <string>
#include <pthread.h>

#include "LinkList.h"
#include "C2JNexus.h"
#include "../DataNet/RDMAComm.h"
#include "../Merger/MergeManager.h"
#include "AIOHandler.h"
#include "InputClient.h"

class C2JNexus;
class MergeManager;
struct reduce_task;

enum compressionType{compOff, compSnappy, compLzo};

typedef struct reduce_directory {
    char         *path;
    list_head_t   list;
} reduce_directory_t;

typedef struct merging_state {

//    InputClient       *client;

    int                online;

    memory_pool_t      mop_pool;
    
    int 			   data_port;
} merging_state_t;

typedef struct reduce_task {

	InputClient       *client;

    struct list_head   list;
    int                reduce_id;

    pthread_cond_t     cond;
    pthread_mutex_t    lock;

    int                num_maps;
    char              *job_id;
    char              *reduce_task_id;
    int                mop_index;

    MergeManager      *merge_man;  
    netlev_thread_t    merge_thread;

    memory_pool_t      kv_pool; // size will be: NUM_STAGE_MEM * netlev_kv_pool_size (currently, 2 * 1MB)

    /* for measurement */
    int           total_wait_mem_time;
    int           total_fetch_time;
    int           total_merge_time;
    int           total_upload_time;

    /* debug info */
    int           total_java_reqs;
    int           total_first_fetch;
    int           total_first_return;
    int			  lpq_size;
    int			  buffer_size;
    std::vector<std::string>   local_dirs; // local dirs will serve for lpq temp files

    /*for compression*/

    compressionType comp_alg;
    int comp_block_size;

    bool isCompressionOn(){
    	return (comp_alg != compOff);
    }

    bool isCompressionOff(){
		return !isCompressionOn();
	}

    compressionType getCompressionType(){
    	return comp_alg;
    }

    void setCompressionType(compressionType _comp_alg){
    	comp_alg = _comp_alg;
    }

    compressionType resetCompression(){
    	compressionType _comp_alg = comp_alg;
    	comp_alg = compOff;
    	return _comp_alg;
    }

public:
    void                 init(); // just initialization and calculation without starting a thread
    void                 start();// start a thread for fetch/merge
    merging_state_t     *getMergingSm() {return the_merging_sm;}
private:
    merging_state_t     *the_merging_sm; //pointer to the global merging_sm

} reduce_task_t;

typedef struct double_buffer {
    int		buffer1;
    int		buffer2;
} double_buffer_t;

void reduce_exit_msg_handler();
void reduce_downcall_handler(const std::string & msg);
extern reduce_task_t * g_task; // we only support 1 reducer per process
void spawn_reduce_task();
void finalize_reduce_task(reduce_task_t *task);
int  create_mem_pool(int logsize, int num, memory_pool_t *pool);
void createInputClient();
compressionType getCompAlg(char* comp);
double_buffer_t calculateMemPool(int minRdmaBuffer);

#endif

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
