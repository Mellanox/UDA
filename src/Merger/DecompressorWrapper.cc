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

    log(lsDEBUG, "length is %d", block_size);
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
    log(lsDEBUG, "dtor DecompressorWrapper");
}




void copy_from_side_buffer_to_actual_buffer(mem_desc_t * dest, char *side_buffer, int length){
	log(lsTRACE, "before copy end is %d length is %d", dest->end, length);
	//write in a single step
	if (length <= dest->buf_len - dest->end){
		memcpy(dest->buff + dest->end, side_buffer, length);
		dest->end += length;
		dest->free_bytes -= length;
	}
	//write in two steps
	else
	{
		int size_copy_first_round = dest->buf_len - dest->end;
		memcpy(dest->buff + dest->end, side_buffer, size_copy_first_round);
		int size_copy_second_round = length - size_copy_first_round;
		memcpy(dest->buff, side_buffer + size_copy_first_round, size_copy_second_round);
		dest->end = size_copy_second_round;
		dest->free_bytes -= length;
	}
	log(lsTRACE, "after copy end is %d length is %d", dest->end, length);
}



void *decompressMainThread(void* wrapper)
{
	DecompressorWrapper *decompWrapper = (DecompressorWrapper *) wrapper;
	log(lsDEBUG, "decompressMainThread DecompressorWrapper");
	while (!decompWrapper->decompress_thread.stop){
		if (!decompWrapper->req_to_decompress.empty()){
//			log(lsTRACE, "removing req for decompression from queue");

			pthread_mutex_lock(&decompWrapper->lock);
			client_part_req_t *current_req_to_decompress = decompWrapper->req_to_decompress.front();
			decompWrapper->req_to_decompress.pop_front();
			pthread_mutex_unlock(&decompWrapper->lock);

			if (current_req_to_decompress){

				//in the meanwhile data was finished and d-tor of map output was called
				if (!current_req_to_decompress->mop){
					continue;
				}

				//checking if in the meanwhile, all data from rdma buffer was read and a fetch request is in the air.
				if (current_req_to_decompress->request_in_air){
					continue;
				}

				//check if the decompression of this block is still necessary or we already have enough data (unless it is the first fetch)
				if (current_req_to_decompress->mop->fetch_count != 0 &&
					current_req_to_decompress->mop->total_fetched_read  >= current_req_to_decompress->mop->total_len_raw) {
						log(lsTRACE, "we already have enough data for mop#%d: currently: %d. with next block it will be %d, while part_len is %d",
						current_req_to_decompress->mop->mop_id, current_req_to_decompress->mop->total_fetched_read,
						current_req_to_decompress->mop->total_fetched_read + decompWrapper->reduce_task->block_size, current_req_to_decompress->mop->total_len_raw);
					continue;

				}

				/*checking if there is free space to decompress a block. it is possible there won't be space: for example if several requests were entered to the queue
				 *  one after another and there was enough space for only one block
				 *  TODO: to consider having a data structure, that will hold a sinlge instance per MOF and only once it will be removed a new one would be added */
				if (current_req_to_decompress->mop->task->block_size > current_req_to_decompress->mop->getFreeBytes()){
//					log(lsTRACE, "there is no free space to copy a block. block size is %d, free space is %d",
//							current_req_to_decompress->mop->task->block_size, current_req_to_decompress->mop->getFreeBytes());
					continue;
				}


				mem_desc_t * rdma_mem_desc = current_req_to_decompress->mop->mop_bufs[0];

				//TODO: save this data instead of reading it again
				decompressRetData_t* next_block_size = decompWrapper->get_next_block_length(rdma_mem_desc->buff + rdma_mem_desc->start);

				log(lsTRACE, "mop_id is %d, uncompr is %d, compr is %d total_fetched_read is %d total_len_raw is %d total_len_part is %d rdma_start is %d",
						current_req_to_decompress->mop->mop_id, next_block_size->num_uncompressed_bytes, next_block_size->num_compressed_bytes,
						current_req_to_decompress->mop->total_fetched_read,  current_req_to_decompress->mop->total_len_raw, current_req_to_decompress->mop->total_len_part, rdma_mem_desc->start);


				/* checking if in the meanwhile rdma buffer was emptied. it is possible that 2 requests were entered to the queue and the first one
				read the last compressed block
				*/
				if (rdma_mem_desc->buf_len - rdma_mem_desc->start - decompWrapper->getBlockSizeOffset() < next_block_size->num_compressed_bytes){
					log(lsTRACE, "in the meanwhile rdma buffer was emptied! ");
					continue;
				}


				log(lsTRACE, "sending request to decompression with block size=%d", next_block_size->num_compressed_bytes);

				//note that we should skip the bytes indicating the length of the block

				decompressRetData_t* retData = decompWrapper->decompress(rdma_mem_desc->buff + rdma_mem_desc->start + decompWrapper->getBlockSizeOffset(), decompWrapper->buffer,
						next_block_size->num_compressed_bytes, next_block_size->num_uncompressed_bytes, 0);

				log(lsTRACE, "after decompression for mop %d rdma_mem_desc ->start=%d next_block_size=%d", current_req_to_decompress->mop->mop_id, rdma_mem_desc ->start, next_block_size->num_compressed_bytes);

				rdma_mem_desc->start += next_block_size->num_compressed_bytes + decompWrapper->getBlockSizeOffset();

				mem_desc_t * read_mem_desc = current_req_to_decompress->mop->mop_bufs[1];

				pthread_mutex_lock(&read_mem_desc->lock); //lock something on the reading side

				copy_from_side_buffer_to_actual_buffer(read_mem_desc, decompWrapper->buffer, retData->num_uncompressed_bytes);
				log(lsTRACE, "just copied %d bytes from side buffer to actual buffer", retData->num_uncompressed_bytes);

				pthread_mutex_unlock(&read_mem_desc->lock);

				current_req_to_decompress->mop->total_fetched_read += retData->num_uncompressed_bytes;

				//TODO : make it a different lock?
				pthread_mutex_lock(&decompWrapper->lock);
				current_req_to_decompress->bytes_in_air -= retData->num_uncompressed_bytes;
				pthread_mutex_unlock(&decompWrapper->lock);


				delete (retData);
				delete (next_block_size);

				current_req_to_decompress->mop->task->merge_man->mark_req_as_ready(current_req_to_decompress);
				current_req_to_decompress->mop->fetch_count++;



				//checking if we finished data in rdma buffer and can send a fetch request:
				if (current_req_to_decompress->mop->total_fetched_raw < current_req_to_decompress->mop->total_len_part){
					mem_desc_t *rdmaBuffer = current_req_to_decompress->mop->mop_bufs[0];
					decompressRetData_t* next_block_length = decompWrapper->get_next_block_length(rdmaBuffer->buff + rdmaBuffer->start);
					if (rdmaBuffer->buf_len - rdmaBuffer->start - decompWrapper->getBlockSizeOffset() < next_block_length->num_compressed_bytes && !current_req_to_decompress->request_in_air){ //check of req_in_air is redundant??
						int leftover_prevoius_block = rdmaBuffer->buf_len - rdmaBuffer->start;

					   log(lsTRACE, "should send a new fetch request - rewinding %d bytes so we would read a whole block", leftover_prevoius_block);

					   current_req_to_decompress->mop->total_fetched_raw -= leftover_prevoius_block;
					   log(lsTRACE, "mop->total_fetched_raw=%d mop->total_len_part=%d ", current_req_to_decompress->mop->total_fetched_raw, current_req_to_decompress->mop->total_len_part);

					   decompWrapper->getRdmaClient()->start_fetch_req(current_req_to_decompress);
					   current_req_to_decompress->request_in_air = true;

					}

				}

			}
		}
		else{
			pthread_mutex_lock(&decompWrapper->lock);
			pthread_cond_wait(&decompWrapper->cond, &decompWrapper->lock);
			pthread_mutex_unlock(&decompWrapper->lock);
		}
	}
}


void DecompressorWrapper::start_client(){
	this->rdmaClient=new RdmaClient(port, this->reduce_task);
	this->rdmaClient->start_client();

	//start decompress thread
	memset(&this->decompress_thread, 0, sizeof(netlev_thread_t));
	this->decompress_thread.stop = 0;
	pthread_attr_init(&this->decompress_thread.attr);
	pthread_attr_setdetachstate(&this->decompress_thread.attr, PTHREAD_CREATE_JOINABLE);
	log(lsINFO, "CREATING THREAD"); pthread_create(&this->decompress_thread.thread,
		                       &this->decompress_thread.attr,
		                       decompressMainThread, this);

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



int DecompressorWrapper::start_fetch_req(client_part_req_t *req) //called by the merge thread (similar to what's happening now)
{

	//checking if it is the first fetch for this reducer
	if (!req->mop->fetch_count){
		log(lsDEBUG, "this is the first fetch for this mop-id %d", req->mop->mop_id);
		req->request_in_air = true;
		return rdmaClient->start_fetch_req(req);
	}

	//checking if we already have all the data decompressed:
	if (req->mop->total_fetched_read >= req->mop->total_len_raw){
//		log(lsTRACE, "we already have all the data decompressed");
		return 0; //TODO return value
	}

	mem_desc_t *rdmaBuffer = req->mop->mop_bufs[0];

//	 log(lsTRACE, "mopid=%d mop->total_fetched_read=%d mop->total_len_raw=%d free bytes is %d. rdma_start is %d",
//			   req->mop->mop_id, req->mop->total_fetched_read, req->mop->total_len_raw, req->mop->getFreeBytes(), rdmaBuffer->start);


	decompressRetData_t* next_block_length = get_next_block_length(rdmaBuffer->buff + rdmaBuffer->start);


	//checking if there is a whole compressed block in rdmaBuffer
	if (rdmaBuffer->buf_len - rdmaBuffer->start  >= next_block_length->num_compressed_bytes){
		//checking if there is enough space to decompress it
		if (req->mop->getFreeBytes()-req->bytes_in_air >= req->mop->task->block_size ){ //next_block_length->num_uncompressed_bytes
		 	//TODO: should save somewhere the next_block_length: for rdma->offset keep the next block length

			log(lsTRACE, "mopid=%d mop->total_fetched_read=%d mop->total_len_raw=%d free bytes is %d. rdma_start is %d",
						   req->mop->mop_id, req->mop->total_fetched_read, req->mop->total_len_raw, req->mop->getFreeBytes(), rdmaBuffer->start);


//			log(lsTRACE, "this is enough space to decompress another block!");

			//pushing the request to queue and waking up decompressor thread
		 	pthread_mutex_lock(&this->lock);
		 	this->req_to_decompress.push_back(req);
//		 	req->bytes_in_air += next_block_length->num_uncompressed_bytes; //should be a different lock
		 	pthread_mutex_unlock(&this->lock);
			pthread_cond_broadcast(&this->cond); //wakes up decompress thread
	   }
	}
	delete (next_block_length);
//	 TODO: return ?;
}


//this method is being called by the RDMA client thread
void DecompressorWrapper::comp_fetch_req(client_part_req_t *req)
{

	req->mop->mop_bufs[0]->start = 0;
	req->mop->task->merge_man->update_fetch_req(req);
	req->request_in_air = false;
	if (req->mop->getFreeBytes() >= req->mop->task->block_size ){
		pthread_mutex_lock(&this->lock);
		this->req_to_decompress.push_back(req);
		pthread_mutex_unlock(&this->lock);
		pthread_cond_broadcast(&this->cond); //wakes up decompress thread
	}
}



void DecompressorWrapper::initJniEnv(){
	this->jniEnv = attachNativeThread();

}


/**
 * loads symbols from handle library
 */
void* DecompressorWrapper::loadSymbol(void *handle, char *symbol ){
	char *error = NULL;
	void* func_ptr = dlsym(handle, symbol);
	if ((error = dlerror()) != NULL) {
		log(lsERROR,"error loading %s, %s",symbol,error);
		exit (1);
	}
	return func_ptr;
}



/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
