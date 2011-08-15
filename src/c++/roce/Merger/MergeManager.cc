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
#include <limits.h>
#include "MergeQueue.h"
#include "MergeManager.h"
#include "StreamRW.h"
#include "reducer.h"
#include "IOUtility.h"
#include "C2JNexus.h"

#ifndef PATH_MAX  // normally defined in limits.h
#define PATH_MAX 4096
#endif

using namespace std;

extern merging_state_t merging_sm;
        
int num_stage_mem = 2;

#define NUM_LPQS 20 // AVNER: of course - this is very temp

void *upload_online(reduce_task_t *task)
{
    MergeManager *merger = task->merge_man;

	/* now we have only two buffer for staging */
	int cur_idx = 0;

	while (!task->upload_thread.stop) {
		mem_desc_t *desc = merger->merge_queue->staging_bufs[cur_idx];

		pthread_mutex_lock(&desc->lock);

		if ( desc->status != MERGE_READY ) {
			pthread_cond_wait(&desc->cond, &desc->lock);

			if (task->upload_thread.stop) {
				output_stdout(" << %s: BREAKING because of task->upload_thread.stop=%d", __func__, task->upload_thread.stop);
				pthread_mutex_unlock(&desc->lock);
				break;
			}
		}

		output_stdout("%s: writing to nexus desc->act_len=%d", __func__, desc->act_len);

		/* upload */
		task->nexus->send_int((int) desc->act_len);
		task->nexus->stream->write( desc->buff, desc->act_len);

		/* change status */
		desc->status = FETCH_READY;
		++cur_idx;
		if (cur_idx >= num_stage_mem) {
			cur_idx = 0;
		}
		pthread_cond_broadcast(&desc->cond);
		pthread_mutex_unlock(&desc->lock);
	}

    return NULL;
}


void *upload_thread_main(void *context) 
{
    reduce_task_t *task = (reduce_task_t *) context;
    MergeManager *merger = task->merge_man;

    int online = merger->online;
    output_stdout("%s: online=%d; task->num_maps=%d", __func__ , online, task->num_maps);

	switch (online) {
	case 0:
		/* FIXME: on-disk merge*/
		break;
	case 1:
		upload_online (task);
		break;
	case 2: default:
		//upload_hybrid (task);
		upload_online (task);
		break;
	}

    return NULL;
}

/* report progress every 256 map outputs*/
#define PROGRESS_REPORT_LIMIT 20

void *merge_do_fetching_phase (reduce_task_t *task, MergeQueue<Segment*> *merge_queue, int num_maps)
{
    MergeManager *manager = task->merge_man;
    int target_maps_count = manager->total_count + num_maps;
	output_stdout("%s: DEBUG: task->num_maps=%d target_maps_count=%d", __func__, task->num_maps, target_maps_count);
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
				merge_queue->insert(segment);

				/* report */
				manager->total_count++;
				manager->progress_count++;
				output_stdout("%s: segment was inserted: manager->total_count=%d, task->num_maps=%d", __func__, manager->total_count, task->num_maps);

				if (manager->progress_count == PROGRESS_REPORT_LIMIT
				 || manager->total_count == task->num_maps) {
					output_stdout("%s: nexus sending FETCH_OVER_MSG...", __func__ );
					task->nexus->send_int((int)FETCH_OVER_MSG);
					manager->progress_count = 0;
				}

				if (manager->total_count == target_maps_count) {
					break;
				}
			}
		}

		if (manager->total_count == target_maps_count) break;

		pthread_mutex_lock(&manager->lock);
		if (manager->fetched_mops.size() > 0) {
			pthread_mutex_unlock(&manager->lock);
			continue;
		}
		pthread_cond_wait(&manager->cond, &manager->lock);
		pthread_mutex_unlock(&manager->lock);

	} while (true);

    return NULL;
}



void *merge_do_merging_phase (reduce_task_t *task, MergeQueue<Segment*> *merge_queue)
{
	/* merging phase */
	int idx = 0;
	bool b = false;

	while (!task->merge_thread.stop && !b) {
		mem_desc_t *desc = merge_queue->staging_bufs[idx];

		pthread_mutex_lock(&desc->lock);
		if ( desc->status != FETCH_READY
		 &&  desc->status != INIT ) {
		   pthread_cond_wait(&desc->cond, &desc->lock);
		}

		output_stdout("calling write_kv_to_mem desc->buf_len=%d", desc->buf_len);
		b = write_kv_to_mem(merge_queue,
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

    return NULL;
}

void *merge_online (reduce_task_t *task)
{
	merge_do_fetching_phase(task, task->merge_man->merge_queue, task->num_maps);

	write_log(task->reduce_log, DBG_CLIENT, "Enter into merging phase");
	merge_do_merging_phase(task, task->merge_man->merge_queue);
	write_log(task->reduce_log, DBG_CLIENT, "merge thread exit");
    return NULL;
}

void *merge_hybrid (reduce_task_t *task)
{
	if (task->num_maps < NUM_LPQS) return merge_online(task);

	bool b = true;
	int32_t total_write;

/*
	//1st fetch is smaller than subsequent fetches - TODO: make the last one the smallest...
	const int max_maps_in_lpq = (task->num_maps + NUM_LPQS - 1) / NUM_LPQS;
	int num_to_fetch = task->num_maps % max_maps_in_lpq;
	const int subsequent_fetch = max_maps_in_lpq;
	if (!num_to_fetch) num_to_fetch = max_maps_in_lpq;
//*/
	const int regular_lpqs = NUM_LPQS - 1; // all lpqs but the 1st will have same number of segments
	int num_to_fetch = 0;
	int subsequent_fetch = 0;
	if (task->num_maps % regular_lpqs) {
		num_to_fetch = task->num_maps % regular_lpqs; //1st lpq will be smaller than all others
		subsequent_fetch = task->num_maps / regular_lpqs;
	}
	else {
		subsequent_fetch = task->num_maps / NUM_LPQS; // can't use previous attitude
		num_to_fetch = subsequent_fetch + task->num_maps % NUM_LPQS; // put the extra segments in 1st lpq
	}

	MergeQueue<Segment*>* merge_lpq[NUM_LPQS];// = new MergeQueue<Segment*>(subsequent_fetch);
	char temp_file[PATH_MAX];
	for (int i = 0; task->merge_man->total_count < task->num_maps; ++i)
	{
		output_stdout("%s: ====== [%d] Creating LPQ for %d segments (already fetched=%d; num_maps=%d)", __func__ , i, num_to_fetch, task->merge_man->total_count, task->num_maps);
		merge_lpq[i] = new MergeQueue<Segment*>(num_to_fetch);;
		merge_do_fetching_phase(task, merge_lpq[i], num_to_fetch);

		// the right location for this block is in the fetching loop
		// however, it seems to cause problems; hence, it is temporarily
		// moved the building RPQ loop
		sprintf(temp_file, "/data1/NetMerger.%s.lpq-%d", task->reduce_task_id, i);
		output_stdout("%s: [%d] === Enter merging LPQ using file: %s", __func__ ,i, temp_file);
		b = write_kv_to_file(merge_lpq[i], temp_file, total_write);
		output_stdout("%s: ===after merge of LPQ b=%d, total_write=%d", __func__ , (int)b, total_write);
		// end of block from previous loop

		num_to_fetch = subsequent_fetch;
	}

	output_stdout("%s: === ALL LPQs completed  building RPQ...", __func__ );
	for (int i = 0; i < NUM_LPQS ; ++i)
	{
		sprintf(temp_file, "/data1/NetMerger.%s.lpq-%d", task->reduce_task_id, i);
		output_stdout("%s [%d] === inserting LPQ using file: %s", __func__ , i, temp_file);
		task->merge_man->merge_queue->insert(new SuperSegment(task, temp_file));
		output_stdout("%s [%d] === after insert LPQ into RPQ", __func__ , i);
		num_to_fetch = subsequent_fetch;
	}


	//
	// TODO: AVNER: delete merge_lpq:
	// - something like: merge_queue->core_queue.clear(); delete merge_queue;
	//
	for (int i = 0; i < NUM_LPQS ; ++i)
	{
		merge_lpq[i]->core_queue.clear();
		delete merge_lpq[i];
	}

	output_stdout("%s: RPQ phase: going to merge all LPQs...", __func__ );
	merge_do_merging_phase(task, task->merge_man->merge_queue);
	output_stdout("%s: after ALL merge", __func__ );

	write_log(task->reduce_log, DBG_CLIENT, "merge thread exit");
    return NULL;
}


void *merge_thread_main (void *context)
{
    reduce_task_t *task = (reduce_task_t *) context;
    MergeManager *manager = task->merge_man;

    int online = manager->online;
    output_stdout("%s: online=%d; task->num_maps=%d", __func__ , online, task->num_maps);

	switch (online) {
	case 0:
		/* FIXME: on-disk merge*/
		break;
	case 1:
		merge_online (task);
		break;
	case 2: default:
		merge_hybrid (task);
		break;
	}

	output_stdout("%s: finished !!!", __func__);
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

    this->total_count = 0;
    this->progress_count = 0;

    pthread_mutex_init(&this->lock, NULL);
    pthread_cond_init(&this->cond, NULL); 
    
    if (online) {    

    	if (online == 1)
    		merge_queue = new MergeQueue<Segment*>(task->num_maps);
    	else //online == 2
    		merge_queue = new MergeQueue<Segment*>(NUM_LPQS);

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

        merge_queue->core_queue.clear(); //TODO: this should be moved into ~MergeQueue()
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
