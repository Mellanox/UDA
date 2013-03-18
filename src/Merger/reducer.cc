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
#include <algorithm>    // std::min

#include "reducer.h"
#include "IOUtility.h"
#include "C2JNexus.h"
#include "../DataNet/RDMAClient.h"
#include "CompareFunc.h"
#include "LzoDecompressor.h"
#include "SnappyDecompressor.h"
#include <UdaUtil.h>

using namespace std;

#define RDMA_BUFFERS_PER_SEGMENT (2)
#define EXTRA_RDMA_BUFFERS (10)

extern merging_state_t merging_sm;
extern void *merge_thread_main (void *context);

static void init_reduce_task(struct reduce_task *task);

reduce_task_t * g_task;

void handle_init_msg(hadoop_cmd_t *hadoop_cmd)
{
	static const int DIRS_START = 9;

	log(lsDEBUG, "handle_init_msg: got params from java  num_maps=%s, job_id=%s, reduce_task_id=%s, lpq_size=%s, buffer_size_from_java=%s, minBuffer=%s, cmp_func=%s, comp_alg=%s, comp_block_size=%s", hadoop_cmd->params[0],hadoop_cmd->params[1],
			hadoop_cmd->params[2],hadoop_cmd->params[3],hadoop_cmd->params[4],hadoop_cmd->params[5],hadoop_cmd->params[6],hadoop_cmd->params[7],hadoop_cmd->params[8]);

	assert (hadoop_cmd->count -1 > 2); // sanity under debug
	g_task->num_maps = atoi(hadoop_cmd->params[0]);
	g_task->job_id = strdup(hadoop_cmd->params[1]);
	g_task->reduce_task_id = strdup(hadoop_cmd->params[2]);
	g_task->lpq_size = atoi(hadoop_cmd->params[3]);

	int buffer_size_from_java = atoi(hadoop_cmd->params[4]); // unaligned to pagesize

//
	g_task->buffer_size = buffer_size_from_java - buffer_size_from_java % getpagesize(); // alignment to pagesize
	int minRdmaBuffer = atoi(hadoop_cmd->params[5]); // java passes it in Bytes
	log(lsDEBUG, "minRdmaBuffer %d,  g_task->buffer_size*2=%d",minRdmaBuffer,g_task->buffer_size*2 );
	if ( (g_task->buffer_size <= 0) || (g_task->buffer_size < minRdmaBuffer) ) {
		log(lsERROR, "RDMA Buffer is too small: buffer_size_from_java=%dB, pagesize=%d, aligned_buffer_size=%dB, min_buffer=%dB", buffer_size_from_java, getpagesize(), g_task->buffer_size, minRdmaBuffer);
		throw new UdaException("RDMA Buffer is too small");
	}

	g_cmp_func = get_compare_func(hadoop_cmd->params[6]); // set compare func using Java's key type name

	g_task->comp_alg = getCompAlg(hadoop_cmd->params[7]);

	g_task->comp_block_size = atoi(hadoop_cmd->params[8]);

	createInputClient();

	g_task->client->start_client();

	log(lsDEBUG, " AFTER INPUT CLIENT CREATION");
	log(lsDEBUG, "1 minRdmaBuffer %d,  g_task->buffer_size*2=%d, g_task->comp_block_size=%d",minRdmaBuffer,g_task->buffer_size*2,g_task->comp_block_size );
	int num_dirs = 0;

	if (hadoop_cmd->count -1  > DIRS_START) {
		assert (hadoop_cmd->params[DIRS_START] != NULL); // sanity under debug
		if (hadoop_cmd->params[DIRS_START] != NULL) {
			num_dirs = atoi(hadoop_cmd->params[DIRS_START]);
			log(lsDEBUG, " ===>>> num_dirs=%d" , num_dirs);

			assert (num_dirs >= 0); // sanity under debug
			if (num_dirs > 0 && DIRS_START + 1 + num_dirs  <= hadoop_cmd->count - 1) {
				g_task->local_dirs.resize(num_dirs);
				for (int i = 0; i < num_dirs; ++i) {
					g_task->local_dirs[i].assign(hadoop_cmd->params[DIRS_START + 1 + i]);
					log(lsDEBUG, " -> dir[%d]=%s", i, g_task->local_dirs[i].c_str());
				}
			}
		}
	}
	log(lsDEBUG, "2 minRdmaBuffer %d,  g_task->buffer_size*2=%d, g_task->comp_block_size=%d",minRdmaBuffer,g_task->buffer_size*2,g_task->comp_block_size );
	initMemPool(minRdmaBuffer);

	init_reduce_task(g_task);
}

void reduce_downcall_handler(const string & msg)
{
	client_part_req_t   *req;
	hadoop_cmd_t        *hadoop_cmd;
	

	hadoop_cmd = (hadoop_cmd_t*) malloc(sizeof(hadoop_cmd_t));

// hadoop_cmd = new hadoop_cmd_t();
// std::auto_ptr<hadoop_cmd_t> auto_hadoop_cmd(hadoop_cmd)
	
	memset(hadoop_cmd, 0, sizeof(hadoop_cmd_t));

	/* if hadoop command could not be parsed correctly */
	if(!parse_hadoop_cmd(msg, *hadoop_cmd))
	{
		log(lsWARN, "Hadoop's command  - %s could not be parsed", msg.c_str());
		free_hadoop_cmd(*hadoop_cmd);
		free(hadoop_cmd);
		throw new UdaException("C++ could not parse Hadoop command");
	}
	log(lsDEBUG, "===>>> GOT COMMAND FROM JAVA SIDE (total %d params): hadoop_cmd->header=%d ", hadoop_cmd->count - 1, (int)hadoop_cmd->header);

	switch (hadoop_cmd->header) {
	case INIT_MSG: {
		handle_init_msg(hadoop_cmd);
		free_hadoop_cmd(*hadoop_cmd);
		free(hadoop_cmd);
		break;
	}
	case FETCH_MSG:
		/*
		 * 1. find the hostid
		 * 2. map from the hostid to its request list
		 * 3. lock the list and insert the new request
		 */

		/* Insert a segment request into the list */
		req = (client_part_req_t *) malloc(sizeof(client_part_req_t));
		memset(req, 0, sizeof(client_part_req_t));
		req->info = hadoop_cmd;
		req->mop = NULL;
		pthread_mutex_lock(&g_task->merge_man->lock);
		g_task->merge_man->fetch_list.push_back(req);

		pthread_cond_broadcast(&g_task->merge_man->cond);
		pthread_mutex_unlock(&g_task->merge_man->lock);

		write_log(g_task->reduce_log, DBG_CLIENT,
				"Got 1 more fetch request, total is %d",
				++g_task->total_java_reqs);

		break;

	case FINAL_MSG:
		/* do the final merge */
		pthread_mutex_lock(&g_task->merge_man->lock);
		g_task->merge_man->flag = FINAL_MERGE;
		pthread_cond_broadcast(&g_task->merge_man->cond);
		pthread_mutex_unlock(&g_task->merge_man->lock);
		free_hadoop_cmd(*hadoop_cmd);
		free(hadoop_cmd);
		break;

	case EXIT_MSG:
		finalize_reduce_task(g_task);
		free_hadoop_cmd(*hadoop_cmd);
		free(hadoop_cmd);
		break;
	BULLSEYE_EXCLUDE_BLOCK_START
	default:
		free_hadoop_cmd(*hadoop_cmd);
		free(hadoop_cmd);
		break;
	}
	BULLSEYE_EXCLUDE_BLOCK_END

	log(lsDEBUG, "<<<=== HANDLED COMMAND FROM JAVA SIDE");
}


void init_mem_desc(mem_desc_t *desc, char *addr, int32_t buf_len){
	desc->buff  = addr;
	desc->buf_len = buf_len;
	desc->status = INIT;
	desc->start = 0;
	desc->end = 0;
	pthread_mutex_init(&desc->lock, NULL);
	pthread_cond_init(&desc->cond, NULL);
}



int  create_mem_pool(int size, int num, memory_pool_t *pool) //similar to the old one
//buffers come in pair and might be of different size
{
    int pagesize = getpagesize();
    uint64_t buf_len;

    pthread_mutex_init(&pool->lock, NULL);
    INIT_LIST_HEAD(&pool->free_descs);

    buf_len = size;
    pool->num = num;
    pool->total_size = buf_len * num;

    log (lsDEBUG, "buffer length is %d, pool->total_size is %d\n", buf_len, pool->total_size);
    
    int rc = posix_memalign((void**)&pool->mem,  pagesize, pool->total_size);
    BULLSEYE_EXCLUDE_BLOCK_START
	if (rc) {
    	log(lsERROR, "Failed to memalign. aligment=%d size=%ll , rc=%d", pagesize ,pool->total_size, rc );
        throw new UdaException("memalign failed");
    }
    BULLSEYE_EXCLUDE_BLOCK_END

    log(lsDEBUG,"memalign successed - %lld bytes", pool->total_size);
    memset(pool->mem, 0, pool->total_size);

    for (int i = 0; i < num; ++i) {
        mem_desc_t *desc = (mem_desc_t *) malloc(sizeof(mem_desc_t));
        init_mem_desc(desc, pool->mem + i * buf_len, buf_len);
        pthread_mutex_lock(&pool->lock);
        list_add_tail(&desc->list, &pool->free_descs);
        pthread_mutex_unlock(&pool->lock);
    }
    return 0;
}

//yyyyyyyyyyyyyyyyyyy
int  create_mem_pool_pair(int size1, int size2, int num, memory_pool_t *pool)
//TODO: merge this with create_mem_pool method
//buffers come in pair and might be of different size
{
    int pagesize = getpagesize();

    pthread_mutex_init(&pool->lock, NULL);
    INIT_LIST_HEAD(&pool->free_descs);

    uint64_t num_buf_pairs = num;
    pool->num = num;
    pool->total_size = num_buf_pairs*(size1 + size2);

    log (lsDEBUG, "buffer length1  is %d, buffer length2  is %d pool->total_size is %d\n", size1, size2, pool->total_size);

    int rc = posix_memalign((void**)&pool->mem,  pagesize, pool->total_size);
    BULLSEYE_EXCLUDE_BLOCK_START
    if (rc) {
    	log(lsERROR, "Failed to memalign. aligment=%d size=%ll , rc=%d", pagesize ,pool->total_size, rc );
        throw new UdaException("memalign failed");
    }
    BULLSEYE_EXCLUDE_BLOCK_END

    log(lsDEBUG,"memalign successed - %lld bytes", pool->total_size);
    memset(pool->mem, 0, pool->total_size);

    for (int i = 0; i < num; ++i) {
    	//init mem_desc of the pair
        mem_desc_t *desc1 = (mem_desc_t *) malloc(sizeof(mem_desc_t));
        init_mem_desc(desc1, pool->mem + i * (size1+size2), size1);
        mem_desc_t *desc2 = (mem_desc_t *) malloc(sizeof(mem_desc_t));
        init_mem_desc(desc2, pool->mem + i * (size1+size2)+size1, size2);

        mem_set_desc_t *pair_desc = (mem_set_desc_t *) malloc(sizeof(mem_set_desc_t));
        pair_desc->buffer_unit[0] = desc1;
        pair_desc->buffer_unit[1] = desc2;

        pthread_mutex_lock(&pool->lock);
        list_add_tail(&pair_desc->list, &pool->free_descs);
        pthread_mutex_unlock(&pool->lock);
    }
    return 0;
}



static void init_reduce_task(struct reduce_task *task)
{
    write_log(task->reduce_log, DBG_CLIENT, 
              "%s launched", 
              task->reduce_task_id); 

    write_log(task->reduce_log, DBG_CLIENT, 
             "Total Map is %d", 
             task->num_maps);     
    
    int num_lpqs;
    if (task->lpq_size > 0) {
    	num_lpqs = (task->num_maps / task->lpq_size);
    	// if more than one segment left then additional lpq added
    	// if only one segment left then the first will be larger
    	if ((task->num_maps % task->lpq_size) > 1) 
    		num_lpqs++;
    } else {
        num_lpqs = (int) sqrt(task->num_maps);
    }

    /* Initialize a merge manager thread */
    task->merge_man = new MergeManager(1, merging_sm.online, task, num_lpqs);

    memset(&task->merge_thread, 0, sizeof(netlev_thread_t));
    task->merge_thread.stop = 0;
    task->merge_thread.context = task;
    pthread_attr_init(&task->merge_thread.attr);
    pthread_attr_setdetachstate(&task->merge_thread.attr, 
                                PTHREAD_CREATE_JOINABLE); 
    uda_thread_create(&task->merge_thread.thread,
                   &task->merge_thread.attr, 
                   merge_thread_main, task);
}

void spawn_reduce_task()
{
    int netlev_kv_pool_size;

    g_task = (reduce_task_t *) malloc(sizeof(reduce_task_t));
    memset(g_task, 0, sizeof(*g_task));
    pthread_cond_init(&g_task->cond, NULL);
    pthread_mutex_init(&g_task->lock, NULL);

    g_task->mop_index = 0;

    /* init large memory pool for merged kv buffer */
    memset(&g_task->kv_pool, 0, sizeof(memory_pool_t));
    netlev_kv_pool_size  = 1 << NETLEV_KV_POOL_EXPO;

    BULLSEYE_EXCLUDE_BLOCK_START
    if (create_mem_pool(netlev_kv_pool_size, NUM_STAGE_MEM, &g_task->kv_pool)) {
    	log(lsERROR, "failed to create memory pool for reduce g_task for merged kv buffer");
    	throw new UdaException("failed to create memory pool for reduce g_task for merged kv buffer");
    }
    BULLSEYE_EXCLUDE_BLOCK_END
    /* report success spawn to java */
//    g_task->nexus->send_int((int)RT_LAUNCHED);
}



//------------------------------------------------------------------------------
void final_cleanup(){

	log(lsINFO, "-------------- STOPING PROCESS ---------");
    /* free map output pool */
    while (!list_empty(&merging_sm.mop_pool.free_descs)) {
    	mem_set_desc_t *desc_pair = list_entry(merging_sm.mop_pool.free_descs.next,
                       typeof(*desc_pair), list);
        list_del(&desc_pair->list);
        for (int i=0; i<NUM_STAGE_MEM; i++){
        	 free (desc_pair->buffer_unit[i]);
        }
        free(desc_pair);
    }
    pthread_mutex_destroy(&merging_sm.mop_pool.lock);
    free(merging_sm.mop_pool.mem);
    log (lsDEBUG, "mop pool is freed");

    g_task->client->stop_client();
    log (lsDEBUG, "INPUT client is stopped");

    delete(g_task->client);
    log (lsDEBUG, "INPUT client is deleted");

}

//------------------------------------------------------------------------------
void finalize_reduce_task(reduce_task_t *task) 
{
   /* for measurement please enable the codes and set up your directory */
	log(lsINFO, "-------------- STOPING REDUCER ---------");

    write_log(task->reduce_log, DBG_CLIENT,
              "Total wait  time: %d", 
              task->total_wait_mem_time);

    /* stop merge thread and upload thread - This will only happen after joining fetch_thread*/
    task->merge_thread.stop = 1;
    pthread_mutex_lock(&task->merge_man->lock);
    pthread_cond_broadcast(&task->merge_man->cond);
    pthread_mutex_unlock(&task->merge_man->lock);
	log(lsDEBUG, "<< before joining merge_thread");
    pthread_join(task->merge_thread.thread, NULL); log(lsDEBUG, "THREAD JOINED");
	log(lsDEBUG, "-------------->>> merge_thread has joined <<<<------------");

    delete task->merge_man;
   
    /* free large pool */
	int rc=0;
    log(lsTRACE, ">> before free pool loop");
    while (!list_empty(&task->kv_pool.free_descs)) {
        mem_desc_t *desc = 
            list_entry(task->kv_pool.free_descs.next, 
                       typeof(*desc), list);
        list_del(&desc->list);
        if ((rc=pthread_cond_destroy(&desc->cond))) {
        	log(lsERROR, "Failed to destroy pthread_cond - rc=%d", rc);
        }
        if ((rc=pthread_mutex_destroy(&desc->lock))) {
        	log(lsERROR, "Failed to destroy pthread_mutex - rc=%d", rc);
        }
        free(desc);
    }
	log(lsTRACE, "<< after  free pool loop");
    pthread_mutex_destroy(&task->kv_pool.lock);
    free(task->kv_pool.mem);
    write_log(task->reduce_log, DBG_CLIENT, "kv pool is freed");

    if ((rc=pthread_cond_destroy(&task->cond))) {
    	log(lsERROR, "Failed to destroy pthread_cond - rc=%d", rc);
    }
    if ((rc=pthread_mutex_destroy(&task->lock))) {
    	log(lsERROR, "Failed to destroy pthread_mutex - rc=%d", rc);
    }

    final_cleanup();
    
    free(task->reduce_task_id);
    free(task->job_id);
    free(task);

    log(lsINFO, "*********  ALL C++ threads finished  ************");
    closeLog();
}

void createInputClient(){
	compressionType comp = g_task->getCompressionType();
	switch(comp){
		case compOff:
			g_task->client = new RdmaClient(merging_sm.data_port, g_task);
			log (lsDEBUG, "creating rdma client");
		break;
		case compLzo:
			g_task->client = new LzoDecompressor(merging_sm.data_port, g_task);
			log (lsDEBUG, "creating lzo client");
		break;
		case compSnappy:
			g_task->client = new SnappyDecompressor(merging_sm.data_port, g_task);
			log (lsDEBUG, "creating snappy client");
		break;
		default:
			log(lsERROR, "compression not supported: %d", comp);
			throw new UdaException("compression not supported");
		break;
	}
}

compressionType getCompAlg(char* comp){
	if(strcmp(comp,"com.hadoop.compression.lzo.LzoCodec")==0){
		return compLzo;
	}else if(strcmp(comp,"org.apache.hadoop.io.compress.SnappyCodec")==0){
		return compSnappy;
	}else if(strcmp(comp,"null")==0){
		return compOff;
	}else{
		log(lsERROR, "compression not supported: %s", comp);
		throw new UdaException("compression not supported");
	}
}

//XXXXXXXXXXXXX

void initMemPool(int minRdmaBuffer){

	int rc=0;
	// init map output memory pool
	memset(&merging_sm.mop_pool, 0, sizeof(memory_pool_t));
	int numBuffers = g_task->num_maps + EXTRA_RDMA_BUFFERS; //the buffers will be allocated in pairs
	log(lsINFO, "RDMA buffer size: %dB (aligned to pagesize)", g_task->buffer_size);

	if (g_task->isCompressionOff()) {//if not compression
		log(lsDEBUG, "init. compression not configured: allocating 2 buffers of same size = %d",g_task->buffer_size);
		rc = create_mem_pool_pair(g_task->buffer_size, g_task->buffer_size,numBuffers,&merging_sm.mop_pool);

	} else{
		float splitPercentRdmaComp =  ::atof(UdaBridge_invoke_getConfData_callback ("mapred.rdma.compression.buffer.ratio", "0.20").c_str());
		int maxRdmaSize =  ::atof(UdaBridge_invoke_getConfData_callback ("mapred.rdma.buf.size", "1024").c_str());
		int uncompBufferHardMin = g_task->comp_block_size + minRdmaBuffer;
		int totalBufferPerMof = g_task->buffer_size * 2;
		if(totalBufferPerMof < uncompBufferHardMin + minRdmaBuffer)
		{
			log(lsERROR, "not enough memory to allocate buffers. minRdmaBuffer=%d, uncompBufferHardMin=%d, totalBufferPerMof=%d, splitPercentRdmaComp=%f",minRdmaBuffer, uncompBufferHardMin, totalBufferPerMof, splitPercentRdmaComp);
            throw new UdaException ("not enough memory to allocate buffers");
		}

		int delta = totalBufferPerMof - (uncompBufferHardMin + minRdmaBuffer);
		log(lsDEBUG, " initMemPool. delta = %d, minRdmaBuffer = %d, uncompBufferHardMin = %d",delta,minRdmaBuffer,uncompBufferHardMin);
		int uncompBufferUsed = uncompBufferHardMin + (int)(delta * splitPercentRdmaComp);
		int rdmaBufferUsed = totalBufferPerMof - uncompBufferUsed;

		//rdma buffer size is limited by 1M. if the calculation yields a bigger buffer we move the spare memory to the compression buffer
		int spare = max(rdmaBufferUsed - maxRdmaSize , 0);
		rdmaBufferUsed -= spare;
		uncompBufferUsed += spare;

		log(lsDEBUG, " initMemPool2. uncompBufferUsed = %d, rdmaBufferUsed=%d",uncompBufferUsed,rdmaBufferUsed);

		rc = create_mem_pool_pair(rdmaBufferUsed, uncompBufferUsed, numBuffers, &merging_sm.mop_pool);

		/* PLEASE DON'T CHANGE THE FOLLOWING LINE - THE AUTOMATION PARSE IT */
		log(lsINFO, "init compression configured. allocating rdmaBufferUsed = %d uncompBufferUsed = %d totalBufferPerMof = %d", uncompBufferHardMin, totalBufferPerMof);
	}

	if(rc){
		log(lsERROR, "failed to create Map Output memory pool");
		throw new UdaException("failed to create Map Output memory pool");
	}

	// register RDMA buffers
	g_task->client->getRdmaClient()->register_mem(&merging_sm.mop_pool);
	/* PLEASE DON'T CHANGE THE FOLLOWING LINE - THE AUTOMATION PARSE IT */
	log(lsINFO, " After RDMA buffers registration (%d buffers X %d bytes = total %lld bytes)", numBuffers, g_task->buffer_size, merging_sm.mop_pool.total_size);

}

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
