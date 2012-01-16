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

#include <set>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/time.h>
#include <pthread.h>
#include <malloc.h>

#include "C2JNexus.h"
#include "IOUtility.h"
#include "../DataNet/RDMAClient.h"
#include "NetlevComm.h"
#include "InputClient.h"

class InputClient;
class MergeManager;
class MapOutput;
struct reduce_task;

extern merging_state merging_sm;
    
void *fetch_thread_main(void *context) 
{
    reduce_task_t  *task;
    FetchManager   *fetch_man;
//    host_list      *host;

    task = (reduce_task_t *) context;
    fetch_man = task->fetch_man;

    while (!task->fetch_thread.stop) {

        while (! fetch_man->fetch_list.empty()) {
            client_part_req *fetch_req = NULL;
            pthread_mutex_lock(&fetch_man->send_lock);
            fetch_req = fetch_man->fetch_list.front();
            fetch_man->fetch_list.pop_front();
            pthread_mutex_unlock(&fetch_man->send_lock);

            if (fetch_req) {
                fetch_man->start_fetch_req(fetch_req);
            }
        }

        /* 1: check if there are more fetch requests. */ 
        pthread_mutex_lock(&fetch_man->send_lock);
        if (! fetch_man->fetch_list.empty() ) {
            pthread_mutex_unlock(&fetch_man->send_lock);
            continue;
        }
//        log(lsTRACE, "before fetch thread waiting on send_cond");
        pthread_cond_wait(&fetch_man->send_cond, &fetch_man->send_lock);
//        log(lsTRACE, "after fetch thread waiting on send_cond");
        pthread_mutex_unlock(&fetch_man->send_lock);

    }

    log(lsDEBUG, "fetch thread exit");
    write_log(task->reduce_log, DBG_CLIENT, "fetch thread exit");
    return NULL;
}

FetchManager::FetchManager(reduce_task_t *task)
{
    this->task = task;
    pthread_mutex_init(&this->send_lock, NULL);
    pthread_cond_init(&this->send_cond, NULL);
}

FetchManager::~FetchManager()
{
    pthread_mutex_destroy(&this->send_lock);
    pthread_cond_destroy(&this->send_cond);
}

int FetchManager::start_fetch_req(client_part_req_t *req)
{
    if (!req->mop) {
        req->mop = new MapOutput(this->task); 
        req->mop->part_req = req;
        req->mop->fetch_count = 0;
        task->total_first_fetch += 1;
    } 

    /* Update the buf status */
    req->mop->mop_bufs[req->mop->staging_mem_idx]->status = BUSY;
  
    int ret = merging_sm.client->start_fetch_req(req);
    log(lsDEBUG, "after start_fetch_req from host=%s ret=%d", req->info->params[0], ret);
    if ( ret == 0 ) {
        if (req->mop->fetch_count == 0) {
            write_log(task->reduce_log, DBG_CLIENT,
                     "First time fetch: %d destination: %s", 
                      task->total_first_fetch,
                      req->info->params[0]);
        }
    } else if(ret == -2) {
        if (req->mop->fetch_count == 0) {
            write_log(task->reduce_log, DBG_CLIENT,
                     "First time fetch request is in backlog: %d", 
                     task->total_first_fetch);
        }
    } else {
        if (req->mop->fetch_count == 0) {
            log(lsERROR, "First time fetch is lost %d", task->total_first_fetch);
        }
    }
    
    return 1;
}

int FetchManager::update_fetch_req(client_part_req_t *req)
{ 
    /* 
     * 1. mark memory available again
     * 2. increase MOF offset and set length
     */
    uint64_t recvd_data[3];    
    int i = 0;
    bool in_queue = false;

    /* format: "rawlength:partlength:recv_data" */
    recvd_data[0] = atoll(req->recvd_msg);
    while (req->recvd_msg[i] != ':' ) { ++i; }
    recvd_data[1] = atoll(req->recvd_msg + (++i));
    while (req->recvd_msg[i] != ':' ) { ++i; }
    recvd_data[2] = atoll(req->recvd_msg + (++i));

    MergeManager *merger = req->mop->task->merge_man;
    in_queue = (req->mop->fetch_count != 0);
        /*(merger->mops_in_queue.find(req->mop->mop_id) 
        != merger->mops_in_queue.end());*/
    req->last_fetched = recvd_data[2];
    req->total_len    = recvd_data[1];

    pthread_mutex_lock(&req->mop->lock);
    /* set variables in map output */
    req->mop->total_len      = req->total_len;
    req->mop->total_fetched += req->last_fetched;
    req->mop->mop_bufs[req->mop->staging_mem_idx]->status = MERGE_READY;
    pthread_mutex_unlock(&req->mop->lock);

    if (!in_queue) {
        // Insert into merge manager fetched_mops
		log(lsTRACE, "Inserting into merge manager fetched_mops...");
        pthread_mutex_lock(&merger->lock);
        merger->fetched_mops.push_back(req->mop);
        pthread_cond_broadcast(&merger->cond);
        /* write_log(task->reduce_log, DBG_CLIENT, 
                  "First time return: %d", 
                  ++task->total_first_return); */
        pthread_mutex_unlock(&merger->lock);
    } else {
        /* wake up the merging thread */
		log(lsTRACE, "Got subsequent chunk for existing segment"); // TODO: remove this log
        //pthread_mutex_lock(&req->mop->lock);
        pthread_cond_broadcast(&req->mop->cond); 
        //pthread_mutex_unlock(&req->mop->lock);
        //pthread_cond_broadcast(&merger->cond);
    } 
    //pthread_cond_broadcast(&req->mop->cond);
   
    return 1;
}

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
