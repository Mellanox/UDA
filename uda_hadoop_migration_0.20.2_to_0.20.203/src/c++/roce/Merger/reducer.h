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

#ifndef NETLEV_REDUCER_H
#define NETLEV_REDUCER_H      1

#include <list>
#include <string>
#include <map>
#include <set>
#include <pthread.h>

#include "LinkList.h"
#include "C2JNexus.h"
#include "../DataNet/RDMAComm.h"
#include "../Merger/MergeManager.h"
#include "../Merger/FetchManager.h"

class InputClient;
class C2JNexus;
class MergeManager;
struct reduce_task;

typedef struct reduce_directory {
    char         *path;
    list_head_t   list;
} reduce_directory_t;

typedef struct merging_state {

    pthread_mutex_t    lock;  /* lock for the global state machine */
    pthread_cond_t     cond;  /* conditional signal for thread activation */

    C2JNexus          *nexus;    /* control channel */
    InputClient       *client;   /* Transport */

    volatile int       stop;
    int                online;

    struct list_head   socket_list;
    struct list_head   dir_list;
    struct list_head   task_list;
    
    memory_pool_t      mop_pool; 

} merging_state_t;

typedef struct reduce_socket {
    struct list_head   list;
    int                sock_fd;
    int                reduce_id;
} reduce_socket_t;

typedef struct reduce_task {
    struct list_head   list;
    int                sock_fd;
    int                reduce_id;

    pthread_cond_t     cond;
    pthread_mutex_t    lock;

    int                num_maps;
    char              *job_id;
    char              *reduce_task_id;
    int                mop_index;

    std::map <std::string, host_list_t *> *hostmap;

    C2JNexus          *nexus;
    FetchManager      *fetch_man;
    netlev_thread_t    fetch_thread;

    MergeManager      *merge_man;  
    netlev_thread_t    merge_thread;

    /* The thread upload merged data to java */
    netlev_thread_t    upload_thread; 

    memory_pool_t      kv_pool; 

    FILE              *reduce_log;

    /* for measurement */
    int           total_wait_mem_time;
    int           total_fetch_time;
    int           total_merge_time;
    int           total_upload_time;

    /* debug info */
    int           total_java_reqs;
    int           total_first_fetch;
    int           total_first_return;
} reduce_task_t;

reduce_task_t *spawn_reduce_task(int mode, reduce_socket_t *sock);
void finalize_reduce_task(reduce_task_t *task);
int  create_mem_pool(int logsize, int num, memory_pool_t *pool);

#endif

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
