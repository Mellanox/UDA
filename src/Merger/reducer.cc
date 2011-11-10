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

#include <iostream>
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/types.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <stdlib.h>
#include <malloc.h>
#include <ctime>
#include <assert.h>
#include <math.h> //for sqrt

#include "reducer.h"
#include "InputClient.h"
#include "IOUtility.h"
#include "C2JNexus.h"

using namespace std;

extern merging_state_t merging_sm;
extern int num_stage_mem;
extern void *fetch_thread_main (void *context);
extern void *merge_thread_main (void *context);
extern void *upload_thread_main(void *context);

static void init_reduce_task(struct reduce_task *task);

static void reduce_downcall_handler(progress_event_t *pevent, void *ctx)
{
    reduce_task_t       *task;
    C2JNexus            *nexus;
    //host_list_t         *host;
    client_part_req_t   *req;
    hadoop_cmd_t        *hadoop_cmd;

    task = (reduce_task_t *) ctx;
    nexus = task->nexus;
    hadoop_cmd = (hadoop_cmd_t*) malloc(sizeof(hadoop_cmd_t));
    memset(hadoop_cmd, 0, sizeof(hadoop_cmd_t));

    string msg = nexus->recv_string();
    parse_hadoop_cmd(msg, *hadoop_cmd);
    
    output_stdout("%s: ===>>> GOT COMMAND FROM JAVA SIDE (total %d params): hadoop_cmd->header=%d ", __func__, hadoop_cmd->count - 1, (int)hadoop_cmd->header);

    if ( hadoop_cmd->header == INIT_MSG ) {
        assert (hadoop_cmd->count -1 > 2); // sanity under debug
        task->num_maps = atoi(hadoop_cmd->params[0]); 
        task->job_id = strdup(hadoop_cmd->params[1]);
        task->reduce_task_id = strdup(hadoop_cmd->params[2]);

        const int DIRS_START = 3;
        if (hadoop_cmd->count -1  > DIRS_START) {
        	assert (hadoop_cmd->params[DIRS_START] != NULL); // sanity under debug
        	if (hadoop_cmd->params[DIRS_START] != NULL) {
			int num_dirs = atoi(hadoop_cmd->params[DIRS_START]);
			output_stdout("%s: ===>>> num_dirs=%d" , __func__, num_dirs);

			assert (num_dirs >= 0); // sanity under debug
			if (num_dirs > 0 && DIRS_START + 1 + num_dirs  <= hadoop_cmd->count - 1) {
				task->local_dirs.resize(num_dirs);
				for (int i = 0; i < num_dirs; ++i) {
					task->local_dirs[i].assign(hadoop_cmd->params[DIRS_START + 1 + i]);
					output_stdout("%s: -> dir[%d]=%s" , __func__, i, task->local_dirs[i].c_str());
				}
			}
        	}
        }
        init_reduce_task(task);
        free_hadoop_cmd(*hadoop_cmd);
        free(hadoop_cmd);
        return;
    } 

    if ( hadoop_cmd->header == FETCH_MSG) {
        /* 
        * 1. find the hostid
        * 2. map from the hostid to its request list
        * 3. lock the list and insert the new request 
        */
        //string hostid = hadoop_cmd->params[0];        
        
        /* map<string, host_list_t *>::iterator iter;
        host = NULL;
        bool is_new = false;

        pthread_mutex_lock(&task->lock);
        iter = task->hostmap->find(hostid);
        if (iter == task->hostmap->end()) {
            host = (host_list_t *) malloc(sizeof(host_list_t));
            pthread_mutex_init(&host->lock, NULL);
            INIT_LIST_HEAD(&host->todo_fetch_list);
            host->hostid = strdup(hostid.c_str());
            (*(task->hostmap))[hostid] = host;
            is_new = true;
        } else {
            host = iter->second;
        }
        pthread_mutex_unlock(&task->lock); */

        /* Insert a segment request into the list */
        req = (client_part_req_t *) malloc(sizeof(client_part_req_t));
        memset(req, 0, sizeof(client_part_req_t));
        req->info = hadoop_cmd;
        /* req->host = host; */
        req->total_len = 0;
        req->last_fetched = 0;
        req->mop = NULL;


        pthread_mutex_lock(&task->fetch_man->send_lock);
        task->fetch_man->fetch_list.push_back(req);
        pthread_cond_broadcast(&task->fetch_man->send_cond);
        pthread_mutex_unlock(&task->fetch_man->send_lock);
        
        /* pthread_mutex_lock(&host->lock);
        list_add_tail(&req->list, &host->todo_fetch_list);
        pthread_mutex_unlock(&host->lock);

        pthread_mutex_lock(&task->fetch_man->send_req_lock);
        if (is_new) {
            list_add_tail(&host->list, &task->fetch_man->send_req_list);
        }
        task->fetch_man->send_req_count++;
        pthread_mutex_unlock(&task->fetch_man->send_req_lock);*/
        
        /* wake up fetch thread */
        //pthread_cond_broadcast(&task->cond);
        
        write_log(task->reduce_log, DBG_CLIENT, 
                  "Got 1 more fetch request, total is %d", 
                  ++task->total_java_reqs);
        return;
    }

    if ( hadoop_cmd->header == FINAL_MSG ) {
        /* do the final merge */
        pthread_mutex_lock(&task->merge_man->lock);
        task->merge_man->flag = FINAL_MERGE;
        pthread_cond_broadcast(&task->merge_man->cond);
        pthread_mutex_unlock(&task->merge_man->lock);
        free_hadoop_cmd(*hadoop_cmd);
        free(hadoop_cmd);
        return;
    }

    if (hadoop_cmd->header == EXIT_MSG ) {
        finalize_reduce_task(task);
        free_hadoop_cmd(*hadoop_cmd);
        free(hadoop_cmd);
        return;
    }
}


int  create_mem_pool(int logsize, int num, memory_pool_t *pool)
{
    int pagesize = getpagesize();
    int32_t buf_len;
    int rc;

    pthread_mutex_init(&pool->lock, NULL);
    INIT_LIST_HEAD(&pool->free_descs);

    buf_len = (1 << logsize);
    pool->logsize = logsize;
    pool->num = num;
    pool->total_size = buf_len * num;
    
    rc = posix_memalign((void**)&pool->mem,  pagesize, pool->total_size);
    if (rc) {
    	output_stderr("unable to create pool. posix_memalign failed: alignment=%d , total_size=%u --> rc=%d", pagesize, pool->total_size, rc );
        return -1;
    }
    memset(pool->mem, 0, pool->total_size);

    for (int i = 0; i < num; ++i) {
        mem_desc_t *desc = (mem_desc_t *) malloc(sizeof(mem_desc_t));
        desc->buff  = pool->mem + i * buf_len;
        desc->buf_len = buf_len;
        desc->owner = pool;
        desc->status = INIT;
        pthread_mutex_init(&desc->lock, NULL);
        pthread_cond_init(&desc->cond, NULL);

        pthread_mutex_lock(&pool->lock);
        list_add_tail(&desc->list, &pool->free_descs);
        pthread_mutex_unlock(&pool->lock);
    }
    return 0;
}

static void init_reduce_task(struct reduce_task *task)
{
    /* Initialize log for reduce task */
    task->reduce_log = create_log(task->reduce_task_id);
    write_log(task->reduce_log, DBG_CLIENT, 
              "%s launched", 
              task->reduce_task_id); 

    write_log(task->reduce_log, DBG_CLIENT, 
             "Total Map is %d", 
             task->num_maps);     
    
    int num_lpqs = (int) sqrt(task->num_maps);
    /* Initialize a merge manager thread */
    task->merge_man = new MergeManager(1, &merging_sm.dir_list,
                                       merging_sm.online, 
                                       task,
                                       num_lpqs);

    memset(&task->merge_thread, 0, sizeof(netlev_thread_t));
    task->merge_thread.stop = 0;
    task->merge_thread.context = task;
    pthread_attr_init(&task->merge_thread.attr);
    pthread_attr_setdetachstate(&task->merge_thread.attr, 
                                PTHREAD_CREATE_JOINABLE); 
    pthread_create(&task->merge_thread.thread, 
                   &task->merge_thread.attr, 
                   merge_thread_main, task);

    /* Initialize a fetcher */
    task->fetch_man = new FetchManager(task);
    memset(&task->fetch_thread, 0, sizeof(netlev_thread_t));
    task->fetch_thread.stop = 0;
    task->fetch_thread.context = task;
    pthread_attr_init(&task->fetch_thread.attr); 
    pthread_attr_setdetachstate(&task->fetch_thread.attr, 
                                PTHREAD_CREATE_JOINABLE);
    pthread_create(&task->fetch_thread.thread, 
                   &task->fetch_thread.attr, 
                   fetch_thread_main, task);

    /* Initialize upload thread to transfer 
       merged data back to java */
    memset(&task->upload_thread, 0, sizeof(netlev_thread_t));
    task->upload_thread.stop = 0;
    task->upload_thread.context = task;
    pthread_attr_init(&task->upload_thread.attr);
    pthread_attr_setdetachstate(&task->upload_thread.attr,
                                PTHREAD_CREATE_JOINABLE);
    pthread_create(&task->upload_thread.thread,
                   &task->upload_thread.attr,
                   upload_thread_main, task);
}

reduce_task_t *spawn_reduce_task(int mode, reduce_socket_t *sock) 
{
    reduce_task_t     *task;
    //int               ret;

    task = (reduce_task_t *) malloc(sizeof(reduce_task_t));
    memset(task, 0, sizeof(*task));
    pthread_cond_init(&task->cond, NULL);
    pthread_mutex_init(&task->lock, NULL);

    if (mode == INTEGRATED) {
        task->sock_fd = sock->sock_fd;
        task->reduce_id = sock->reduce_id;
    } else {
        static int stand_alone_reduce_id = 0;
        task->reduce_id = stand_alone_reduce_id++;
        task->sock_fd = -1;
    }

    task->nexus = 
        new C2JNexus(mode, task->sock_fd, task, 
                     reduce_downcall_handler);

    if (task->nexus == NULL) {
        free(task);
        return NULL;
    }
    
    task->mop_index = 0;
    task->hostmap = 
        new std::map <string, host_list_t *>();

    /* init large memory pool for merged kv buffer */ 
    memset(&task->kv_pool, 0, sizeof(memory_pool_t));

    if (create_mem_pool(NETLEV_KV_POOL_EXPO, num_stage_mem, &task->kv_pool)) {
    	output_stderr("[%s,%d] failed to create memory pool for reduce task for merged kv buffer",__FILE__,__LINE__);
    	exit(-1);
    }

  
    /* report success spawn to java */ 
    task->nexus->send_int((int)RT_LAUNCHED);
    return task;
}

void finalize_reduce_task(reduce_task_t *task) 
{
   /* for measurement please enable the codes and set up your directory */
	log(lsTRACE, "function started");

    write_log(task->reduce_log, DBG_CLIENT, 
              "Total merge time: %d",  
              task->total_merge_time);
    write_log(task->reduce_log, DBG_CLIENT, 
              "Total upload time: %d", 
              task->total_upload_time);
    write_log(task->reduce_log, DBG_CLIENT, 
              "Total wait  time: %d", 
              task->total_wait_mem_time);
    write_log(task->reduce_log, DBG_CLIENT, 
              "Total fetch time: %d", 
              task->total_fetch_time);

    delete task->nexus; 
    write_log(task->reduce_log, DBG_CLIENT, 
              "%s nexus thread joined",
              task->reduce_task_id);


    /* stop fetch thread */ 
    task->fetch_thread.stop = 1;
    pthread_mutex_lock(&task->lock);
    pthread_cond_broadcast(&task->cond);
    pthread_mutex_unlock(&task->lock);
    pthread_join(task->fetch_thread.thread, NULL);
    delete task->fetch_man;
    write_log(task->reduce_log, DBG_CLIENT, 
              "fetch thread joined");
    
    /* stop merge thread and upload thread */
    task->upload_thread.stop = 1;
    task->merge_thread.stop = 1;
    pthread_mutex_lock(&task->merge_man->lock);
    pthread_cond_broadcast(&task->merge_man->cond);
    pthread_mutex_unlock(&task->merge_man->lock);
    pthread_join(task->merge_thread.thread, NULL);  
    delete task->merge_man;
    write_log(task->reduce_log, DBG_CLIENT, 
              "merge thread joined");
   
    /* delete map */
    /* map <string, host_list_t*>::iterator iter =
        task->hostmap->begin();
    while (iter != task->hostmap->end()) {
        free((iter->second)->hostid);
        free(iter->second);
        iter++;
    }
    delete task->hostmap;
    DBGPRINT(DBG_CLIENT, "host lists and map are freed\n"); */

    /* free large pool */
    while (!list_empty(&task->kv_pool.free_descs)) {
        mem_desc_t *desc = 
            list_entry(task->kv_pool.free_descs.next, 
                       typeof(*desc), list);
        list_del(&desc->list);
        free(desc);
    }
    pthread_mutex_destroy(&task->kv_pool.lock);
    free(task->kv_pool.mem);
    write_log(task->reduce_log, DBG_CLIENT, 
              "kv pool is freed");

    pthread_mutex_destroy(&task->lock);
    pthread_cond_destroy(&task->cond);
   
    pthread_mutex_lock(&merging_sm.lock);
    list_del(&task->list);
    pthread_mutex_unlock(&merging_sm.lock);
    
    
    write_log(task->reduce_log, DBG_CLIENT, 
              "reduce task is freed successfully");
    close_log(task->reduce_log);   
    
    free(task->reduce_task_id);
    free(task->job_id);
    free(task);
	log(lsTRACE, "function ended");
}

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
