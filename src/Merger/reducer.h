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

typedef struct reduce_directory {
    char         *path;
    list_head_t   list;
} reduce_directory_t;

typedef struct merging_state {

//    InputClient       *client;

    int                online;

    memory_pool_t      mop_pool;
    
    int 			data_port;


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

    memory_pool_t      kv_pool; 

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
    char *compr_alg;
    int block_size;
} reduce_task_t;

void reduce_downcall_handler(const std::string & msg);
extern reduce_task_t * g_task; // we only support 1 reducer per process
void spawn_reduce_task();
void finalize_reduce_task(reduce_task_t *task);
int  create_mem_pool(int logsize, int num, memory_pool_t *pool);
int  create_mem_pool_pair(int size1, int size2,  int num, memory_pool_t *pool);
#endif

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
