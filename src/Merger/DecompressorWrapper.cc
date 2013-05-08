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



DecompressorWrapper::DecompressorWrapper(int port, reduce_task_t* reduce_t) : reduce_task (reduce_t), buffer(NULL)
{
    //allocating side buffer
    int block_size = this->reduce_task->comp_block_size;
    this->buffer = (char *) malloc(block_size * sizeof(char));

    pthread_cond_init(&this->cond, NULL);
    pthread_mutex_init(&this->lock, NULL);

    this->rdmaClient=new RdmaClient(port, this->reduce_task);

    memset(&this->decompress_thread, 0, sizeof(netlev_thread_t));
	this->decompress_thread.stop = 0;
	this->decompress_thread.context = this;
	//this->decompress_thread.pollfd = 0;
	pthread_attr_init(&this->decompress_thread.attr);
	pthread_attr_setdetachstate(&this->decompress_thread.attr, PTHREAD_CREATE_JOINABLE);

    log(lsDEBUG, "ctor DecompressorWrapper");
}

DecompressorWrapper::~DecompressorWrapper()
{
	free(this->buffer);
	this->buffer = NULL;
	delete (this->rdmaClient);
	this->rdmaClient = NULL;
	pthread_mutex_destroy(&this->lock);
	pthread_cond_destroy(&this->cond);
    log(lsDEBUG, "dtor DecompressorWrapper");
}




void DecompressorWrapper::copy_from_side_buffer_to_actual_buffer(mem_desc_t * dest, uint32_t length)
{
	//write in a single step
	if (dest->end + length <= dest->buf_len){
		memcpy(dest->buff + dest->end, this->buffer, length);
		dest->end += length;
	}
	//write in two steps
	else
	{
		int size_copy_first_round = dest->buf_len - dest->end;
		memcpy(dest->buff + dest->end, this->buffer, size_copy_first_round);
		int size_copy_second_round = length - size_copy_first_round;
		memcpy(dest->buff, this->buffer + size_copy_first_round, size_copy_second_round);
		dest->end = size_copy_second_round;
	}
}

/*static method */void *DecompressorWrapper::decompressMainThread(void* wrapper)
{
	return ((DecompressorWrapper*)wrapper) -> decompressMainThread();
}

void *DecompressorWrapper::decompressMainThread()
{
	while (!this->decompress_thread.stop){
		if (!this->req_to_decompress.empty()){

			pthread_mutex_lock(&this->lock);
			client_part_req_t *req = this->req_to_decompress.front();
			this->req_to_decompress.pop_front();
			pthread_mutex_unlock(&this->lock);

			if (req){
				// Here we do all the work!
				handle1Req(req);

				//send new rdma fetch request if necessary
				handleNextRdmaFetch(req);
			}
		}
		else{  // queue is empty => sleep...

			pthread_mutex_lock(&this->lock);
			if (this->req_to_decompress.empty()){
				pthread_cond_wait(&this->cond, &this->lock);
			}
			pthread_mutex_unlock(&this->lock);
		}
	}

	return 0;
}

bool DecompressorWrapper::perliminaryCheck1Req(client_part_req_t *req)
{

	// CODEREVIEW: try removing!
	// sanity; might be irrelevant!
	bool ret = false;
	do {
		if (!req->mop){
			break;
		}


		// CODEREVIEW: consider removing it
		// sanity - may not be needed, since we checked it before insertion to queue
		if (req->mop->fetched_len_uncompress  >= req->mop->total_len_uncompress) { // check if decompression was already finished
			if (req->mop->fetch_count != 0) { // skip in first fetch because fields in above check are not initialized
				log(lsDEBUG, "we already have enough data for mop#%d: currently: %d. with next block it will be %d, while part_len is %d",
						req->mop->mop_id, req->mop->fetched_len_uncompress,
						req->mop->fetched_len_uncompress + this->reduce_task->comp_block_size, req->mop->total_len_uncompress);
				break;
			}
		}

		mem_desc_t * rdma_mem_desc = req->mop->mop_bufs[0];

		//checking if in the meanwhile, all data from rdma buffer was read and a fetch request is in the air.
		if (rdma_mem_desc->status != MERGE_READY){
			break;
		}

		/*checking if there is free space to decompress a block. it is possible there won't be space: for example if several requests were entered to the queue
		 *  one after another and there was enough space for only one block
		 *  TODO: to consider having a data structure, that will hold a sinlge instance per MOF and only once it will be removed a new one would be added */
		if (req->mop->task->comp_block_size > req->mop->getFreeBytes()){
			break;
		}

		/* checking if in the meanwhile rdma buffer was emptied. it is possible that 2 requests were entered to the queue and the first one
					read the last compressed block
		 */
		if (rdma_mem_desc->buf_len - rdma_mem_desc->start - this->getBlockSizeOffset() < this->getNumCompressedBytes(rdma_mem_desc->buff + rdma_mem_desc->start)){
			break;
		}

		ret = true; // success !!!
	}
	while (false);

	req-> request_in_queue = ret;
	return ret;
}

void DecompressorWrapper::doDecompress(client_part_req_t *req)
{
	mem_desc_t * rdma_mem_desc = req->mop->mop_bufs[0];
	mem_desc_t * read_mem_desc = req->mop->mop_bufs[1]; // cyclic buffer

	//note that we should skip the bytes indicating the length of the block
	decompressRetData_t next_block_length;
	this->get_next_block_length(rdma_mem_desc->buff + rdma_mem_desc->start,&next_block_length);
	log(lsTRACE, "mopid=%d, going to decompress data. num_compressed=%d, num_uncompressed=%d, rdma->start=%d, comp->start=%d, comp->end=%d",req->mop->mop_id, next_block_length.num_compressed_bytes, next_block_length.num_uncompressed_bytes, rdma_mem_desc->start, read_mem_desc->start, read_mem_desc->end);
	decompressRetData_t retData;
	//there is enough space in the cyclic buffer for the uncompressed block without doing wrap around = > decompress straight to the cyclic buffer
	if (read_mem_desc->end + next_block_length.num_uncompressed_bytes <= read_mem_desc->buf_len){
		this->decompress(rdma_mem_desc->buff + rdma_mem_desc->start + this->getBlockSizeOffset(),read_mem_desc->buff + read_mem_desc->end,
				next_block_length.num_compressed_bytes, next_block_length.num_uncompressed_bytes, 0,&retData);
		read_mem_desc->end += retData.num_uncompressed_bytes;
		log(lsTRACE, "mopid=%d, just decompressed %d bytes to actual buffer, start=%d, end=%d", req->mop->mop_id, retData.num_uncompressed_bytes, read_mem_desc->start,read_mem_desc->end);
	}else{
		this->decompress(rdma_mem_desc->buff + rdma_mem_desc->start + this->getBlockSizeOffset(),this->buffer,
				next_block_length.num_compressed_bytes, next_block_length.num_uncompressed_bytes, 0,&retData);
		copy_from_side_buffer_to_actual_buffer(read_mem_desc, retData.num_uncompressed_bytes);
		log(lsTRACE, "mopid=%d, just copied %d bytes from side buffer to actual buffer, start=%d, end=%d", req->mop->mop_id, retData.num_uncompressed_bytes, read_mem_desc->start,read_mem_desc->end);
	}
	log(lsTRACE, "changing rdma start. mof=%d, old=%d, new=%d",req->mop->mop_id, rdma_mem_desc->start , rdma_mem_desc->start + retData.num_compressed_bytes + this->getBlockSizeOffset());
	rdma_mem_desc->incStartWithLock(retData.num_compressed_bytes + this->getBlockSizeOffset());




	req->mop->fetched_len_uncompress += retData.num_uncompressed_bytes;
}

void DecompressorWrapper::handleNextRdmaFetch(client_part_req_t *req)
{

	if (req->mop->fetched_len_rdma >= req->mop->total_len_rdma){
		req-> request_in_queue = false;
		return;
	}
	mem_desc_t * rdma_mem_desc = req->mop->mop_bufs[0];
	if (rdma_mem_desc->status != MERGE_READY) {
		req-> request_in_queue = false;
		return;
	}

	// do we already have enough compressed data?
	if (rdma_mem_desc->buf_len  > rdma_mem_desc->start + this->getBlockSizeOffset()) {
		if (rdma_mem_desc->buf_len - rdma_mem_desc->start - this->getBlockSizeOffset() >= getNumCompressedBytes(rdma_mem_desc->buff + rdma_mem_desc->start)) {
			req-> request_in_queue = false;
			return;
		}
	}

	// we need additional compressed data
	int leftover_prevoius_block = rdma_mem_desc->buf_len - rdma_mem_desc->start;
	log(lsTRACE, "sending rdma request for mof=%d, leftover_prevoius_block=%d", req->mop->mop_id, leftover_prevoius_block);

	{
		// must keep order of operations below!

		rdma_mem_desc->status = BUSY;
		req-> request_in_queue = false;

		//Move the leftover to the beginning of the rdma buffer
		memmove (rdma_mem_desc->buff, rdma_mem_desc->buff + rdma_mem_desc->start, leftover_prevoius_block);

		this->getRdmaClient()->start_fetch_req(req, rdma_mem_desc->buff + leftover_prevoius_block, rdma_mem_desc->buf_len - leftover_prevoius_block);
	}
}


void DecompressorWrapper::handle1Req(client_part_req_t *req)
{
	if (!perliminaryCheck1Req(req)) return;

	doDecompress(req);

	req->mop->task->merge_man->mark_req_as_ready(req);
	req->mop->fetch_count++;
}


void DecompressorWrapper::start_client(){

	this->rdmaClient->start_client();

	//start decompress thread
	uda_thread_create(&this->decompress_thread.thread,&this->decompress_thread.attr,DecompressorWrapper::decompressMainThread, this);

	log(lsDEBUG, "start_client DecompressorWrapper");
}

void DecompressorWrapper::stop_client()
{
	this->decompress_thread.stop = 1;

	//waking up decompress thread
	pthread_mutex_lock(&this->lock);
	pthread_cond_broadcast(&this->cond);
	pthread_mutex_unlock(&this->lock);

	pthread_join(this->decompress_thread.thread, NULL); log(lsDEBUG, "THREAD JOINED");

	this->rdmaClient->stop_client();

	log(lsDEBUG, "stop_client DecompressorWrapper");

}


RdmaClient* DecompressorWrapper::getRdmaClient(){
	return (RdmaClient*)this->rdmaClient;
}

//CODEREVIEW: consider splitting into 2 functions:
// 1 - external checks at MergeManager level
// 2 - internal at Decompress Level for internal checks and adding request

// this method is being called by the merger thread (currently after reading each KV)
// it may wake up decompress thread if needed
int DecompressorWrapper::start_fetch_req(client_part_req_t *req, char * buff, int32_t buf_len) //called by the merge thread (similar to what's happening now)
{
	//checking if it is the first fetch for this reducer
	// this check is safe because this method is called only once before reading uncompressed KVs
	// and later calls will be after reading KVs and decompressor ++ it before notifying the Merger
	if (!req->mop->fetched_len_rdma){
		log(lsDEBUG, "this is the first fetch for this mop-id %d", req->mop->mop_id);
		return rdmaClient->start_fetch_req(req, req->mop->mop_bufs[0]->buff, req->mop->mop_bufs[0]->buf_len);
	}

	//checking if we already have all the data decompressed:
	if (req->mop->fetched_len_uncompress >= req->mop->total_len_uncompress){
		return 0;
	}

	mem_desc_t *rdmaBuffer = req->mop->mop_bufs[0];

	if (req->request_in_queue)
		return 0;

	//check if we have enough space in cyclic buffer to decompress block
	if (req->mop->getFreeBytes() < req->mop->task->comp_block_size )
		return 0;

	//check if there's compressed block in rdma buffer to read
	if(!isRdmaBlockReadyToRead(rdmaBuffer))
		return 0;

	//pushing the request to queue and waking up decompressor thread
	pthread_mutex_lock(&this->lock);
	if(!req->request_in_queue) {
		req->request_in_queue = true;
		this->req_to_decompress.push_back(req);
	}
	pthread_cond_broadcast(&this->cond); //wakes up decompress thread
	pthread_mutex_unlock(&this->lock);

	return 0;
}


bool DecompressorWrapper::isRdmaBlockReadyToRead(mem_desc_t *buffer){
	//rdma request was already sent
	if (buffer->status != MERGE_READY)
		return false;
	//not enough data to read size of compressed and uncompressed data nums
	if (buffer->start + getBlockSizeOffset() > buffer->buf_len)
		return false;
	// not enough data to read all block
	if (buffer->buf_len < buffer->start  + getNumCompressedBytes(buffer->buff + buffer->start) + getBlockSizeOffset())
		return false;

	return true;
}


//this method is being called by the RDMA client thread
// it may wake up decompress thread if needed
void DecompressorWrapper::comp_fetch_req(client_part_req_t *req)
{

	mem_desc_t *rdmaBuffer = req->mop->mop_bufs[0];
	rdmaBuffer->start = 0;//CODEREVIEW: is this is the place or it should be in the RDMA fetching
	req->mop->task->merge_man->update_fetch_req(req);

	if(!req->request_in_queue){
		if (req->mop->getFreeBytes() >= req->mop->task->comp_block_size ){
			log(lsTRACE, "comp_fetch_req, mof=%d, req->mop->getFreeBytes()=%d", req->mop->mop_id, (int)req->mop->getFreeBytes());
			pthread_mutex_lock(&this->lock);
				req->request_in_queue = true;
				rdmaBuffer->status=MERGE_READY;
				log(lsTRACE, "pushing comp_fetch mof=%d",req->mop->mop_id);
				this->req_to_decompress.push_back(req);
			pthread_cond_broadcast(&this->cond); //wakes up decompress thread
			pthread_mutex_unlock(&this->lock);

		}else
			rdmaBuffer->status=MERGE_READY;
	} else{
		rdmaBuffer->status=MERGE_READY;
		log(lsERROR, "not supposed to be e request in queue");
	}
}

/**
 * loads symbols from handle library
 */
void* DecompressorWrapper::loadSymbolWrapper(void *handle, const char* symbol ){
	char *error = NULL;
	dlerror();
	void* func_ptr = dlsym(handle, symbol);
	if ((error = dlerror()) != NULL) {
		log(lsERROR,"error loading %s, %s",symbol,error);
		throw new UdaException("Error in loadSymbol");
	}
	return func_ptr;
}



