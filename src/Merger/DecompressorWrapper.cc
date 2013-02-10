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

#include "DecompressorWrapper.h"
#include "StreamRW.h"

using namespace std;



DecompressorWrapper::DecompressorWrapper(int port, reduce_task_t* reduce_task)
{
    this->port = port;
    this->reduce_task = reduce_task;
    this->buffer = NULL;

    //allocating side buffer
    int block_size = this->reduce_task->block_size;

    this->buffer = (char *) malloc(block_size * sizeof(char));
    memset(this->buffer, 0, block_size);

    pthread_cond_init(&this->cond, NULL);
    pthread_mutex_init(&this->lock, NULL);
    log(lsDEBUG, "ctor DecompressorWrapper");
}

DecompressorWrapper::~DecompressorWrapper()
{
	free(this->buffer);
	pthread_mutex_destroy(&this->lock);
	pthread_cond_destroy(&this->cond);
    log(lsDEBUG, "dtor DecompressorWrapper %d");
}




void copy_from_side_buffer_to_actual_buffer(mem_desc_t * dest, char *side_buffer, uint32_t length)
{
	//write in a single step
	if (length <= dest->buf_len - dest->end){
		memcpy(dest->buff + dest->end, side_buffer, length);
		dest->end += length;
	}
	//write in two steps
	else
	{
		int size_copy_first_round = dest->buf_len - dest->end;
		memcpy(dest->buff + dest->end, side_buffer, size_copy_first_round);
		int size_copy_second_round = length - size_copy_first_round;
		memcpy(dest->buff, side_buffer + size_copy_first_round, size_copy_second_round);
		dest->end = size_copy_second_round;
	}
}


void *decompressMainThread(void* wrapper)
{
	DecompressorWrapper *decompWrapper = (DecompressorWrapper *) wrapper;

	while (!decompWrapper->decompress_thread.stop){
		if (!decompWrapper->req_to_decompress.empty()){

			pthread_mutex_lock(&decompWrapper->lock);
			client_part_req_t *current_req_to_decompress = decompWrapper->req_to_decompress.front();
			decompWrapper->req_to_decompress.pop_front();
			pthread_mutex_unlock(&decompWrapper->lock);


			if (current_req_to_decompress){

				//in the meanwhile data was finished and d-tor of map output was called
				if (!current_req_to_decompress->mop){
					current_req_to_decompress-> request_in_queue = false;
					continue;
				}

				mem_desc_t * rdma_mem_desc = current_req_to_decompress->mop->mop_bufs[0];

				//check if the decompression of this block is still necessary or we already have enough data (unless it is the first fetch)
				if (current_req_to_decompress->mop->fetch_count != 0 &&
					current_req_to_decompress->mop->total_fetched_read  >= current_req_to_decompress->mop->total_len_raw) {
						log(lsTRACE, "we already have enough data for mop#%d: currently: %d. with next block it will be %d, while part_len is %d",
						current_req_to_decompress->mop->mop_id, current_req_to_decompress->mop->total_fetched_read,
						current_req_to_decompress->mop->total_fetched_read + decompWrapper->reduce_task->block_size, current_req_to_decompress->mop->total_len_raw);
						current_req_to_decompress-> request_in_queue = false;
				continue;
				}

				mem_desc_t * read_mem_desc = current_req_to_decompress->mop->mop_bufs[1]; // cyclic buffer

				//checking if in the meanwhile, all data from rdma buffer was read and a fetch request is in the air.
				if (rdma_mem_desc->status != MERGE_READY){
					current_req_to_decompress-> request_in_queue = false;
					continue;
				}


				/*checking if there is free space to decompress a block. it is possible there won't be space: for example if several requests were entered to the queue
				 *  one after another and there was enough space for only one block
				 *  TODO: to consider having a data structure, that will hold a sinlge instance per MOF and only once it will be removed a new one would be added */
				if (current_req_to_decompress->mop->task->block_size > current_req_to_decompress->mop->getFreeBytes()){
					current_req_to_decompress-> request_in_queue = false;
					continue;
				}


				decompressRetData_t* next_block_length = new decompressRetData_t();
				decompWrapper->get_next_block_length(rdma_mem_desc->buff + rdma_mem_desc->start,next_block_length);

				/* checking if in the meanwhile rdma buffer was emptied. it is possible that 2 requests were entered to the queue and the first one
				read the last compressed block
				*/
				if (rdma_mem_desc->buf_len - rdma_mem_desc->start - decompWrapper->getBlockSizeOffset() < next_block_length->num_compressed_bytes){
					current_req_to_decompress-> request_in_queue = false;
					delete (next_block_length);
					continue;
				}

				//note that we should skip the bytes indicating the length of the block
				log(lsTRACE, "going to decompress block. mof=%d, compressed=%d, uncompressed=%d",current_req_to_decompress->mop->mop_id, next_block_length->num_compressed_bytes,next_block_length->num_uncompressed_bytes);
				decompressRetData_t* retData = decompWrapper->decompress(rdma_mem_desc->buff + rdma_mem_desc->start + decompWrapper->getBlockSizeOffset(), decompWrapper->buffer,
						next_block_length->num_compressed_bytes, next_block_length->num_uncompressed_bytes, 0);

				pthread_mutex_lock(&rdma_mem_desc->lock);
				log(lsTRACE, "changing rdma start. mof=%d, old=%d, new=%d",current_req_to_decompress->mop->mop_id, rdma_mem_desc->start , rdma_mem_desc->start + retData->num_compressed_bytes + decompWrapper->getBlockSizeOffset());
				rdma_mem_desc->start += retData->num_compressed_bytes + decompWrapper->getBlockSizeOffset();
				pthread_mutex_unlock(&rdma_mem_desc->lock);

				copy_from_side_buffer_to_actual_buffer(read_mem_desc, decompWrapper->buffer, retData->num_uncompressed_bytes);
				log(lsTRACE, "mopid=%d, just copied %d bytes from side buffer to actual buffer, start=%d, end=%d", current_req_to_decompress->mop->mop_id, retData->num_uncompressed_bytes, read_mem_desc->start,read_mem_desc->end);
				current_req_to_decompress->mop->total_fetched_read += retData->num_uncompressed_bytes;

				delete (retData);
				delete (next_block_length);


				current_req_to_decompress->mop->task->merge_man->mark_req_as_ready(current_req_to_decompress);
				current_req_to_decompress->mop->fetch_count++;


				//checking if we finished data in rdma buffer and can send a fetch request:
				if (current_req_to_decompress->mop->total_fetched_raw < current_req_to_decompress->mop->total_len_part){
					mem_desc_t *rdmaBuffer = current_req_to_decompress->mop->mop_bufs[0];

					decompressRetData_t* next_block_length = new decompressRetData_t();
					decompWrapper->get_next_block_length(rdmaBuffer->buff + rdmaBuffer->start,next_block_length);

					if (( (rdmaBuffer->buf_len - rdmaBuffer->start<decompWrapper->getBlockSizeOffset()) ||
							(rdmaBuffer->buf_len - rdmaBuffer->start - decompWrapper->getBlockSizeOffset() < next_block_length->num_compressed_bytes) )
							&& (rdma_mem_desc->status == MERGE_READY)){
						log(lsTRACE, "sending rdma request for mof=%d, rdmaBuffer=%d", current_req_to_decompress->mop->mop_id, rdmaBuffer->buf_len - rdmaBuffer->start);
						rdma_mem_desc->status = BUSY;
						current_req_to_decompress-> request_in_queue = false;
						int leftover_prevoius_block = rdmaBuffer->buf_len - rdmaBuffer->start;
						//copy the leftover to the beginning of the rdma buffer
						memcpy (rdmaBuffer->buff, rdmaBuffer->buff + rdmaBuffer->start, leftover_prevoius_block);

					   decompWrapper->getRdmaClient()->start_fetch_req(current_req_to_decompress, rdmaBuffer->buff + leftover_prevoius_block, rdmaBuffer->buf_len - leftover_prevoius_block);
					}
					else{
						current_req_to_decompress-> request_in_queue = false;
					}

					delete(next_block_length);
				}
				else
					current_req_to_decompress-> request_in_queue = false;
			}
		}
		else{

			pthread_mutex_lock(&decompWrapper->lock);
			if (decompWrapper->req_to_decompress.empty()){
				log(lsTRACE, "going to sleep decomp");
				pthread_cond_wait(&decompWrapper->cond, &decompWrapper->lock);
			}
			pthread_mutex_unlock(&decompWrapper->lock);
		}
	}

	return 0;
}


void DecompressorWrapper::start_client(){
	this->rdmaClient=new RdmaClient(port, this->reduce_task);
	this->rdmaClient->start_client();

	//start decompress thread
	memset(&this->decompress_thread, 0, sizeof(netlev_thread_t));
	this->decompress_thread.stop = 0;
	pthread_attr_init(&this->decompress_thread.attr);
	pthread_attr_setdetachstate(&this->decompress_thread.attr, PTHREAD_CREATE_JOINABLE);
	uda_thread_create(&this->decompress_thread.thread,&this->decompress_thread.attr,decompressMainThread, this);

	initDecompress();
	log(lsDEBUG, "start_client DecompressorWrapper");
}

void DecompressorWrapper::stop_client()
{
	this->decompress_thread.stop = 1;

	//waking up decompress thread
	pthread_mutex_lock(&this->lock);
	pthread_cond_broadcast(&this->cond);
	pthread_mutex_unlock(&this->lock);

	pthread_join(this->decompress_thread.thread, NULL); log(lsINFO, "THREAD JOINED");

	this->rdmaClient->stop_client();
	delete (this->rdmaClient);
	log(lsDEBUG, "stop_client DecompressorWrapper");

}


RdmaClient* DecompressorWrapper::getRdmaClient(){
	return (RdmaClient*)this->rdmaClient;
}



int DecompressorWrapper::start_fetch_req(client_part_req_t *req, char * buff, int32_t buf_len) //called by the merge thread (similar to what's happening now)
{
	//checking if it is the first fetch for this reducer
	// this check is safe because this method is called only once before reading uncompressed KVs
	// and later calls will be after reading KVs and decompressor ++ it before notifying the Merger
	if (!req->mop->total_fetched_raw){
		log(lsDEBUG, "this is the first fetch for this mop-id %d", req->mop->mop_id);
		return rdmaClient->start_fetch_req(req, req->mop->mop_bufs[0]->buff, req->mop->mop_bufs[0]->buf_len);
	}

	//checking if we already have all the data decompressed:
	if (req->mop->total_fetched_read >= req->mop->total_len_raw){
		return 0; //TODO return value
	}

	mem_desc_t *rdmaBuffer = req->mop->mop_bufs[0];
	if((!req->request_in_queue) && (rdmaBuffer->status == MERGE_READY) && (rdmaBuffer->buf_len - rdmaBuffer->start >= getBlockSizeOffset()) ){

		decompressRetData_t* next_block_length = new decompressRetData_t();
		get_next_block_length(rdmaBuffer->buff + rdmaBuffer->start,next_block_length);

		//checking if there is a whole compressed block in rdmaBuffer
		if (rdmaBuffer->buf_len - rdmaBuffer->start  >= next_block_length->num_compressed_bytes + getBlockSizeOffset()){
			//checking if there is enough space to decompress it
			if (req->mop->getFreeBytes() >= req->mop->task->block_size ){ //next_block_length->num_uncompressed_bytes
				//pushing the request to queue and waking up decompressor thread
				pthread_mutex_lock(&this->lock);
				if(!req->request_in_queue) {
					req->request_in_queue = true;
					log(lsTRACE, "pushing start_fetch mof=%d",req->mop->mop_id);
					this->req_to_decompress.push_back(req);
				}
				pthread_cond_broadcast(&this->cond); //wakes up decompress thread
				pthread_mutex_unlock(&this->lock);

		   }
		}
		delete (next_block_length);
	}
	return 0;
}


//this method is being called by the RDMA client thread
void DecompressorWrapper::comp_fetch_req(client_part_req_t *req)
{

	mem_desc_t *rdmaBuffer = req->mop->mop_bufs[0];
	rdmaBuffer->start = 0;
	req->mop->task->merge_man->update_fetch_req(req);
	log(lsTRACE, "after update mof=%d, total=%d",req->mop->mop_id, req->mop->total_fetched_raw);

	if(!req->request_in_queue){
		decompressRetData_t* next_block_length = new decompressRetData_t();
		get_next_block_length(rdmaBuffer->buff + rdmaBuffer->start,next_block_length);

		if (req->mop->getFreeBytes() >= req->mop->task->block_size ){
			log(lsTRACE, "comp_fetch_req, mof=%d, req->mop->getFreeBytes()=%d", req->mop->mop_id, req->mop->getFreeBytes());
			pthread_mutex_lock(&this->lock);
				req->request_in_queue = true;
				rdmaBuffer->status=MERGE_READY;
				log(lsTRACE, "pushing comp_fetch mof=%d",req->mop->mop_id);
				this->req_to_decompress.push_back(req);
			pthread_cond_broadcast(&this->cond); //wakes up decompress thread
			pthread_mutex_unlock(&this->lock);

		}else
			rdmaBuffer->status=MERGE_READY;
		delete (next_block_length);
	} else{
		rdmaBuffer->status=MERGE_READY;
		log(lsERROR, "not supposed to be e request in queue");
	}
}



void DecompressorWrapper::initJniEnv(){
	this->jniEnv = UdaBridge_attachNativeThread();

}


/**
 * loads symbols from handle library
 */
void* DecompressorWrapper::loadSymbol(void *handle, const char* symbol ){
	char *error = NULL;
	void* func_ptr = dlsym(handle, symbol);
	if ((error = dlerror()) != NULL) {
		log(lsERROR,"error loading %s, %s",symbol,error);
		throw new UdaException("Error in loadSymbol");
	}
	return func_ptr;
}

