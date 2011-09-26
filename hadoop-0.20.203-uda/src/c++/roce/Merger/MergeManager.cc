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

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include "StreamRW.h"
#include "MergeQueue.h"
#include "MergeManager.h"
#include "reducer.h"
#include "IOUtility.h"
#include "C2JNexus.h"

using namespace std;

extern merging_state_t merging_sm;
        
int num_stage_mem = 2;

void *upload_thread_main(void *context) 
{
    reduce_task_t *task = (reduce_task_t *) context;
    MergeManager *merger = task->merge_man;
    bool online = merger->online;

    if (online) {
        /* now we have only two buffer for staging */
        int cur_idx = 0;

        while (!task->upload_thread.stop) {
            mem_desc_t *desc = 
              merger->merge_queue->staging_bufs[cur_idx];

            pthread_mutex_lock(&desc->lock);

            if ( desc->status != MERGE_READY ) {
                pthread_cond_wait(&desc->cond, 
                                  &desc->lock);

                if (task->upload_thread.stop) {
                    pthread_mutex_unlock(&desc->lock);
                    break;
                }
            }
 
            /* upload */
            task->nexus->send_int((int) desc->act_len);
            task->nexus->stream->write( desc->buff, 
                                        desc->act_len);

            /* change status */
            desc->status = FETCH_READY;
            ++cur_idx;
            if (cur_idx >= num_stage_mem) {
                cur_idx = 0;
            }
            pthread_cond_broadcast(&desc->cond);
            pthread_mutex_unlock(&desc->lock);
        }
    }
    return NULL;
}

/* report progress every 256 map outputs*/
#define PROGRESS_REPORT_LIMIT 20

void *merge_thread_main (void *context) 
{
    reduce_task_t *task = (reduce_task_t *) context;
    MergeManager *manager = task->merge_man;
    
    bool online = manager->online;

    if (online) { 
        int progress_count = 0; 
        int total_count = 0;
        
        do {
            while (manager->fetched_mops.size() > 0 ) {
                MapOutput *mop = NULL;        

                pthread_mutex_lock(&manager->lock);
                mop = manager->fetched_mops.front();
                manager->fetched_mops.pop_front();
                pthread_mutex_unlock(&manager->lock);
                
                /* not in queue yet */    
                if (manager->mops_in_queue.find(mop->mop_id) 
                    == manager->mops_in_queue.end()) {

                    manager->mops_in_queue.insert(mop->mop_id);
                    Segment *segment = new Segment(mop);
                    manager->merge_queue->insert(segment);
                    
                    /* report */
                    total_count += 1;
                    progress_count += 1;
                    
                    if (progress_count == PROGRESS_REPORT_LIMIT
                     || total_count == task->num_maps) {
                        task->nexus->send_int((int)FETCH_OVER_MSG);
                        progress_count = 0;
                    }
                        
                    if (total_count == task->num_maps) {
                        break;
                    }
                } 
            }
                    
            if (total_count == task->num_maps) break;

            pthread_mutex_lock(&manager->lock);
            if (manager->fetched_mops.size() > 0) {
                pthread_mutex_unlock(&manager->lock);
                continue;
            }
            pthread_cond_wait(&manager->cond, 
                              &manager->lock);
            pthread_mutex_unlock(&manager->lock);
            
        } while (true);
        
        write_log(task->reduce_log, DBG_CLIENT, 
                  "Enter into the merge phase");
           
        /* merging phase */ 
        int idx = 0;
        bool b = false;
        
        while (!task->merge_thread.stop && !b) {
            mem_desc_t *desc = 
              manager->merge_queue->staging_bufs[idx];

            pthread_mutex_lock(&desc->lock);
            if ( desc->status != FETCH_READY 
             &&  desc->status != INIT ) {
               pthread_cond_wait(&desc->cond, 
                                 &desc->lock);
            } 

            b = write_kv_to_mem(manager->merge_queue, 
                                desc->buff, 
                                desc->buf_len,
                                desc->act_len);

            desc->status = MERGE_READY;
            if (!b) {
                ++idx;
                if (idx >= num_stage_mem) {
                    idx = 0;
                }
            }
            pthread_cond_broadcast(&desc->cond);
            pthread_mutex_unlock(&desc->lock);
        }

        write_log(task->reduce_log, DBG_CLIENT, 
                  "merge thread exit");

    } else {
        /* FIXME: on-disk merge*/
    }
    return NULL;
}

/* in-memory map output */
MapOutput::MapOutput(struct reduce_task *task) 
{
    memory_pool_t *mem_pool;

    this->task = task;
    this->staging_mem_idx = 0;
    this->part_req = NULL;
    this->total_len = 0;
    this->total_fetched = 0;
    this->fetch_count = 0;
    pthread_mutex_init(&this->lock, NULL);
    pthread_cond_init(&this->cond, NULL);

    pthread_mutex_lock(&task->lock); 
    mop_id = this->task->mop_index++;
    pthread_mutex_unlock(&task->lock);

    mem_pool = &(merging_sm.mop_pool);
    if(list_empty(&mem_pool->free_descs)) {
        write_log(task->reduce_log, 1, 
                  "no more available mof");
        return;
    }

    pthread_mutex_lock(&mem_pool->lock);
    mop_bufs[0] = list_entry(mem_pool->free_descs.next,
                             typeof(*mop_bufs[0]), list); 
    mop_bufs[0]->status = FETCH_READY;
    list_del(&mop_bufs[0]->list);

    mop_bufs[1] = list_entry(mem_pool->free_descs.next,
                             typeof(*mop_bufs[1]), list); 
    mop_bufs[1]->status = FETCH_READY;
    list_del(&mop_bufs[1]->list);
    pthread_mutex_unlock(&mem_pool->lock);
}

MapOutput::~MapOutput()
{
    part_req->mop = NULL;
    free_hadoop_cmd(*(part_req->info));
    free(part_req->info);
    free(part_req);

    /* return mem */
    memory_pool_t *mem_pool = &(merging_sm.mop_pool);
    pthread_mutex_lock(&mem_pool->lock);
    mop_bufs[0]->status = INIT;
    mop_bufs[1]->status = INIT;
    list_add_tail(&mop_bufs[0]->list, &mem_pool->free_descs);
    list_add_tail(&mop_bufs[1]->list, &mem_pool->free_descs);
    pthread_mutex_unlock(&mem_pool->lock);
    
    pthread_mutex_destroy(&this->lock);
    pthread_cond_destroy(&this->cond);
}

/* The following is for MergeManager */
MergeManager::MergeManager(int threads, list_head_t *list,
                           int online, struct reduce_task *task)
{
    this->task = task;
    this->dir_list = list;
    this->online = online;
    this->flag = INIT_FLAG;
    pthread_mutex_init(&this->lock, NULL);
    pthread_cond_init(&this->cond, NULL); 
    
    if (online) {    
        merge_queue = new MergeQueue(task->num_maps);
        
        /* get staging mem from memory_pool*/
        pthread_mutex_lock(&task->kv_pool.lock);
        for (int i = 0; i < num_stage_mem; ++i) {
            merge_queue->staging_bufs[i] = 
              list_entry(task->kv_pool.free_descs.next,
                         typeof(*merge_queue->staging_bufs[i]), list);
            list_del(&merge_queue->staging_bufs[i]->list);
        }
        pthread_mutex_unlock(&task->kv_pool.lock);
    }
}

MergeManager::~MergeManager()
{
    pthread_mutex_destroy(&lock);
    pthread_cond_destroy(&cond);
    
    if (merge_queue != NULL ) {
        pthread_mutex_lock(&task->kv_pool.lock);
        for (int i = 0; i < num_stage_mem; ++i) {
            mem_desc_t *desc = 
                merge_queue->staging_bufs[i];
            pthread_cond_broadcast(&desc->cond); 
            list_add_tail(&desc->list,
                          &task->kv_pool.free_descs);
        }
        pthread_mutex_unlock(&task->kv_pool.lock);

        merge_queue->core_queue.clear();
        delete merge_queue; 
    }
}

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
