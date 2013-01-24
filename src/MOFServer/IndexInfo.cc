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

#include <fcntl.h>
#include <unistd.h>
#include <sys/time.h>
#include <errno.h>

#include "MOFServlet.h"
#include "IOUtility.h"
#include "IndexInfo.h"
#include "UdaBridge.h"

using namespace std;


enum MEM_STAT {FREE, OCCUPIED, INUSE};


DataEngine::DataEngine(void *mem,
                       supplier_state_t *state,
                       const char *path, int mode, int rdma_buf_size, struct rlimit kernel_fd_rlim)
{

	prepare_tables(mem, rdma_buf_size);

    /* fast mapping from path to partition_table_t */
    this->state_mac = state;
    this->stop = false;
    this->rdma_buf_size = rdma_buf_size;
    this->_kernel_fd_rlim=kernel_fd_rlim;
   
    this->_fdc_map = new map<string, fd_counter_t*> ();
    timespec timeout;
    timeout.tv_nsec=AIOHANDLER_TIMEOUT_IN_NSEC;
    timeout.tv_sec=0;
	log(lsDEBUG, "AIO: creating new AIOHandler with maxevents=%d , min_nr=%d, nr=%d timeout=%ds %lus",AIOHANDLER_CTX_MAXEVENTS, AIOHANDLER_MIN_NR, AIOHANDLER_NR , timeout.tv_sec, timeout.tv_nsec );
	_aioHandler = new AIOHandler(aio_completion_handler, AIOHANDLER_CTX_MAXEVENTS, AIOHANDLER_MIN_NR , AIOHANDLER_NR, &timeout );
	_thread_id=0;


}

#if _BullseyeCoverage
	#pragma BullseyeCoverage off
#endif
void
DataEngine::cleanup_tables()
{
    pthread_mutex_lock(&_data_lock);
    path_fd_iter iter = this->_fdc_map->begin();

    while (iter != this->_fdc_map->end()) {
		fd_counter_t* fdc = iter->second;
		// TODO: cancel all aio operations before surprising the kernel with closed FDs to avoid writing ERROR logs entries by AIO thread
		if(fdc){
			if (fdc->fd)
				close(fdc->fd);
			delete fdc;
    }
		iter++;
	}
    delete(this->_fdc_map);

    pthread_mutex_unlock(&_data_lock);


    pthread_mutex_lock(&this->_chunk_mutex);
    free(this->_chunks);
    pthread_mutex_unlock(&this->_chunk_mutex);


    pthread_mutex_destroy(&this->_data_lock);
    pthread_mutex_destroy(&this->_chunk_mutex);
    pthread_cond_destroy(&this->_chunk_cond);
}
#if _BullseyeCoverage
	#pragma BullseyeCoverage on
#endif

void 
DataEngine::prepare_tables(void *mem, 
                           int rdma_buf_size)
{
    char *data=(char*)mem;

    pthread_mutex_init(&this->_data_lock, NULL);
    pthread_mutex_init(&this->_chunk_mutex, NULL);
    pthread_cond_init(&this->_chunk_cond, NULL);
    INIT_LIST_HEAD(&this->_free_chunks_list);


    pthread_mutex_lock(&this->_chunk_mutex);
    this->_chunks = (chunk_t*)malloc(NETLEV_RDMA_MEM_CHUNKS_NUM * sizeof(chunk_t));
    memset(this->_chunks , 0, NETLEV_RDMA_MEM_CHUNKS_NUM * sizeof(chunk_t));

    log (lsDEBUG, "rdma_buf_size is %d\n", rdma_buf_size);
    for (int i = 0; i < NETLEV_RDMA_MEM_CHUNKS_NUM; ++i) {
        chunk_t *ptr = this->_chunks + i;
        ptr->buff = data + i*(rdma_buf_size + 2*AIO_ALIGNMENT );
        ptr->type = PTR_CHUNK;
        list_add_tail(&ptr->list, &this->_free_chunks_list);
    }
    pthread_mutex_unlock(&this->_chunk_mutex);

}

#if _BullseyeCoverage
	#pragma BullseyeCoverage off
#endif
DataEngine::~DataEngine()
{
    cleanup_tables();
    delete _aioHandler;
}
#if _BullseyeCoverage
	#pragma BullseyeCoverage on
#endif

/**
 * 1. DataEngine pops out requests from global queue 
 * 2. Check the cache
 * 3. Call RdmaServer to send MOF. 
 */
void 
DataEngine::start()
{
	_thread_id = pthread_self();
	_aioHandler->start();

	this->jniEnv = UdaBridge_attachNativeThread();

    /* Wait on the arrival of new MOF files or shuffle requests */
    while (!this->stop) {
        shuffle_req_t *req  = NULL;
        // Process new shuffle requests
        while (!list_empty(&state_mac->mover->incoming_req_list)) {
			pthread_mutex_lock(&state_mac->mover->in_lock);
			req = NULL;
			if (!list_empty(&state_mac->mover->incoming_req_list)) {
				req = list_entry(state_mac->mover->incoming_req_list.next, typeof(*req), list);
				list_del(&req->list);
			}
			pthread_mutex_unlock(&this->state_mac->mover->in_lock);

            if(req) {
            	log(lsDEBUG, "DataEngine: received shuffle request - JOBID=%s REDUCEID=%d offset=%lld", req->m_jobid.c_str(), req->reduceID, req->map_offset);
            	if (req->chunk_size > this->rdma_buf_size) {
            		log(lsERROR, "shuffle request chunk size is larger than rdma buffer(chunk_size=%ld rdma_buf_size=%ld)", req->chunk_size, this->rdma_buf_size);
            		// TODO: report TT for task failure
            		delete req;
            	}
            	else if (process_shuffle_request(req)) {
            		log(lsERROR, "Fail to process shuffle request - JOBID=%s REDUCEID=%d offset=%lld", req->m_jobid.c_str(), req->reduceID, req->map_offset);
            		// TODO: report TT for task failure & add request's retransmit mechanism.
            		delete req;
            	}
            }
        }

        _aioHandler->submit();


        /* check if there is a new incoming shuffle req */
        pthread_mutex_lock(&state_mac->mover->in_lock);
        if (!list_empty(&state_mac->mover->incoming_req_list)){
            pthread_mutex_unlock(&state_mac->mover->in_lock);
            continue;
        }
        pthread_cond_wait(&state_mac->mover->in_cond,
                          &state_mac->mover->in_lock);
		pthread_mutex_unlock(&state_mac->mover->in_lock);
	}

    output_stdout("DataEngine stopped");
}


fd_counter_t* DataEngine::getFdCounter(const string& data_path) {
	fd_counter_t* fdcPtr=NULL;

	pthread_mutex_lock(&this->_data_lock);

	path_fd_iter iter= _fdc_map->find(data_path);

	if (iter == _fdc_map->end()){
		log(lsDEBUG, "create new FD counter for %s", data_path.c_str());

		fdcPtr = new fd_counter_t();
		fdcPtr->fd=0;
		fdcPtr->counter=0;

		fdcPtr->fd = open(data_path.c_str() , O_RDONLY | O_DIRECT);

		if (fdcPtr->fd < 0) {
			log(lsERROR, "open mof %s failed - errno=%m", data_path.c_str());
			if ((errno == EMFILE) && (_kernel_fd_rlim.rlim_max)) {
				log(lsWARN, "Hard rlimit for max open FDs by this process: %lu", _kernel_fd_rlim.rlim_max);
				log(lsWARN, "Soft rlimit for max open FDs by this process: %lu", _kernel_fd_rlim.rlim_cur);
			}
			pthread_mutex_unlock(&this->_data_lock);
			delete fdcPtr;
			return NULL;
		}
		_fdc_map->insert(pair<string, fd_counter_t*>(data_path, fdcPtr)); // in case open file failed, there was "return NULL"
		log(lsDEBUG, "MOF opened: %s", data_path.c_str());
	}
	else {
		fdcPtr=iter->second;
	}

	fdcPtr->counter++; // counts the num of onair aios for this data file

	pthread_mutex_unlock(&this->_data_lock);

	return fdcPtr;
}



int
DataEngine::process_shuffle_request(shuffle_req_t* req) {
    chunk_t* chunk;
    int rc=0;

    index_record_t *index_rec =  UdaBridge_invoke_getPathUda_callback(this->jniEnv, req->m_jobid.c_str(), req->m_map.c_str(), req->reduceID);
    if (!index_rec){
    	log(lsERROR, "UDA bridge failed!");
			return -1;
	}

    // in case we have no more chunks to occupy , then we should submit current aio waiting requests before WAITing for a chunk.
	if (list_empty(&this->_free_chunks_list))
    	_aioHandler->submit();

    // this WAITs on cond in case of no more chunks to occupy
	chunk = occupy_chunk();
    if (chunk == NULL) {
        log(lsERROR, "occupy_chunk failed: jobid=%s, map=%s", req->m_jobid.c_str(), req->m_map.c_str());
        return -1;
    }

    const char *path = jniEnv->GetStringUTFChars(index_rec->path, NULL);
    if (!path){
    	return -1;
    }

    rc= aio_read_chunk_data(req, index_rec, path, chunk, req->map_offset);

    jniEnv->ReleaseStringUTFChars(index_rec->path, path);
    return rc;
}

chunk_t*
DataEngine::occupy_chunk() {
    chunk_t* retval=NULL;

    pthread_mutex_lock(&this->_chunk_mutex);

	if (list_empty(&this->_free_chunks_list)) {
		pthread_cond_wait(&this->_chunk_cond, &this->_chunk_mutex);
	}

	retval= list_entry(this->_free_chunks_list.next, typeof(*retval), list);
	list_del(&retval->list);

	pthread_mutex_unlock(&this->_chunk_mutex);

	return retval;
}

void
DataEngine::release_chunk(chunk_t* chunk) {
    pthread_mutex_lock(&this->_chunk_mutex);
    list_add_tail(&chunk->list, &this->_free_chunks_list);
    pthread_cond_signal(&this->_chunk_cond);
    pthread_mutex_unlock(&this->_chunk_mutex);

}


int DataEngine::aio_read_chunk_data(shuffle_req_t* req , index_record_t* record, const string& outPath, chunk_t* chunk, uint64_t map_offset)
{
    int rc=0;

    int64_t offset = record->offset + map_offset;
    size_t read_length = record->partLength - map_offset;
   	read_length = (read_length < (size_t)req->chunk_size ) ? read_length : req->chunk_size ;
    log (lsDEBUG, "this->rdma_buf_size inside aio_read_chunk_data is %d\n", this->rdma_buf_size);

    fd_counter_t* fdc=getFdCounter(outPath);
    if (!fdc) {
    	const char *path_for_error = jniEnv->GetStringUTFChars(record->path, NULL);
    	if (!path_for_error){
    	   return -1;
    	}
    	log(lsERROR, "fail to get fd counter jobid=%s out_path=%s", req->m_jobid.c_str(), path_for_error);
    	jniEnv->ReleaseStringUTFChars(record->path, path_for_error);
    	return -1;
    }

	req_callback_arg *cb_arg = new req_callback_arg(); // AIOHandler event processor will delete the allocated cb_arg
	cb_arg->chunk=chunk;
    cb_arg->shreq=req;
    cb_arg->state_mac = this->state_mac;
    cb_arg->readLength=read_length;
    cb_arg->record=record;
    cb_arg->offsetAligment= (offset & _aioHandler->ALIGMENT_MASK);
    cb_arg->fdc=fdc;
    cb_arg->fdc_key = outPath;
    size_t length_for_aio = read_length + 2*AIO_ALIGNMENT - (read_length & _aioHandler->ALIGMENT_MASK);

    long new_offset=offset - cb_arg->offsetAligment;
    rc = _aioHandler->prepare_read(fdc->fd, new_offset, length_for_aio, chunk->buff, cb_arg);

    return rc;
}

int aio_completion_handler(void* data, int aio_status) {
	req_callback_arg *req_cb_arg = (req_callback_arg*)data;

	if (!aio_status){
		//aio request ended successfully
		req_cb_arg->state_mac->mover->start_outgoing_req(req_cb_arg->shreq, req_cb_arg->record, req_cb_arg->chunk, req_cb_arg->readLength, req_cb_arg->offsetAligment);
	}//TODO: else: send NACK

	fd_counter_t* fdc=req_cb_arg->fdc;
	DataEngine      *data_eng = req_cb_arg->state_mac->data_mac;

	pthread_mutex_lock(&data_eng->_data_lock);

	fdc->counter--;
	if (!fdc->counter){
		string key=req_cb_arg->fdc_key;
		path_fd_iter iter = data_eng->_fdc_map->find(key);

		//delete from map
		data_eng->_fdc_map->erase(iter);
	}

	pthread_mutex_unlock(&data_eng->_data_lock);
	if (!fdc->counter){
		log(lsDEBUG, "close MOF fd");
		close(fdc->fd);
		delete (fdc);
	}

	delete req_cb_arg->shreq;
	delete req_cb_arg->record;
    delete req_cb_arg;

    return 0;
}

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
*/
