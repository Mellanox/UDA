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

#define EOF_MARKER (-1)
#define __STDC_LIMIT_MACROS
#include <stdint.h>

#include <stdio.h>
#include <map>
#include <ctime>
#include <sys/stat.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>


#include "MergeManager.h"
#include "MergeQueue.h"
#include "StreamRW.h"
#include "IOUtility.h"
#include "reducer.h"

using namespace std;

bool write_kv_to_stream(MergeQueue<BaseSegment*> *records, int32_t len,
		OutStream *stream, int32_t &total_write) {
    int32_t key_len, val_len, bytes_write;
    int32_t kbytes, vbytes;
    int32_t record_len;

    bytes_write = 0;
    key_len = val_len = kbytes = vbytes = 0;
    log(lsINFO, ">>>> started");

    int i = 0;

    while (records->next()) {
    	 if (records->min_segment->get_task()->isCompressionOn()){
			MapOutput *mop = dynamic_cast<MapOutput*>(records->min_segment->getKVOUutput());
			if (mop == NULL) {
				log(lsFATAL, "problem?");
				exit (1);
			}
			//passing NULL and 0 since those variables are needed for RDMA client and not decomressore wrapper
			records->min_segment->get_task()->client->start_fetch_req(mop->part_req, NULL, 0);
		}

        //log(lsTRACE, "in loop i=%d", i++);
        DataStream *k = records->getKey();
        DataStream *v = records->getVal();

		key_len = records->get_key_len();
		val_len = records->get_val_len();

        if (key_len < 0 || val_len < 0) {
            log(lsERROR, "key_len or val_len < 0");
            return true;
        }

		/* check if the entire <k,v> can be written into mem */
        kbytes = records->get_key_bytes();
        vbytes = records->get_val_bytes();

        record_len = kbytes + vbytes + key_len + val_len;
        if ( record_len + bytes_write > len ) {
            total_write = bytes_write;
            records->mergeq_flag = 1;
            log(lsINFO, "return false because record_len + bytes_write > len");
            return false;
        }

        StreamUtility::serializeInt(key_len, *stream);
        StreamUtility::serializeInt(val_len, *stream);
        stream->write(k->getData(), key_len);
        stream->write(v->getData(), val_len);
        bytes_write += record_len;
        records->mergeq_flag   = 0;
        // output_stdout(" << %s: in loop tail <-", __func__);
    }

	/* test for last -1, -1 */
	kbytes = StreamUtility::getVIntSize(EOF_MARKER);
    vbytes = StreamUtility::getVIntSize(EOF_MARKER);
    record_len = kbytes + vbytes;
    if (record_len + bytes_write > len) {
        total_write = bytes_write;
        records->mergeq_flag = 1;
        log(lsINFO, "return false because record_len + bytes_write > len");
        return false;
    }

    /* -1:-1 */
    StreamUtility::serializeInt(EOF_MARKER, *stream);
    StreamUtility::serializeInt(EOF_MARKER, *stream);
    records->mergeq_flag = 0;
	bytes_write += record_len;

	total_write = bytes_write;
    log(lsINFO, "<<<< finished");
    return true;
}




bool write_kv_to_mem(MergeQueue<BaseSegment*> *records, char *src, int32_t len,
		int32_t &total_write) {
    DataStream *stream = new DataStream(src, len);

    bool ret = write_kv_to_stream(records, len, stream, total_write);

    delete stream;
    return ret;
}

Segment::Segment(MapOutput *mapOutput) :
	BaseSegment(mapOutput) {
	this->map_output = mapOutput;
	if (mapOutput) {
		mem_desc_t *mem = kv_output->mop_bufs[kv_output->staging_mem_idx];

		if (get_task()->isCompressionOn()){//compression is on
			this->in_mem_data->reset(mem->buff, mem->end);
		}else{
			this->in_mem_data->reset(mem->buff, mapOutput->last_fetched);
		}
	}

}
/*  The following is for class Segment */
BaseSegment::BaseSegment(KVOutput *kvOutput) {
	log(lsDEBUG, "IDAN BaseSegment CTOR this=%llu", (uint64_t)this);
    this->eof = false;
    this->temp_kv = NULL;
    this->temp_kv_len = 0;
    this->temp_buf = NULL;
    this->temp_buf_len = 0;
    this->cur_key_len = 0;
    this->cur_val_len = 0;
    this->kbytes = 0;
    this->vbytes = 0;
    this->byte_read = 0;

	this->kv_output = kvOutput;
	mem_desc_t *mem;
	if (kvOutput) {
		mem = kv_output->mop_bufs[kv_output->staging_mem_idx];
		this->in_mem_data = new DataStream();
		this->in_mem_data->reset(mem->buff, mem->buf_len);
    }
    else {
    	this->in_mem_data = NULL;
    }
	log(lsDEBUG, "IDAN BaseSegment CTOR finished this=%llu", (uint64_t)this);
}



#if 0
Segment::Segment(const string &path)
{
    this->eof = false;
    this->temp_kv = NULL;
    this->temp_buf = NULL;
    this->temp_buf_len = 0;
    this->temp_kv_len = 0;
    this->cur_key_len = 0;
    this->cur_val_len = 0;
    this->map_output  = NULL;
    this->in_mem_data  = NULL;
    this->path = path;

    this->file = fopen(path.c_str(), "rb");
    if (this->file == NULL) {
        fprintf(stderr,"Reader:cannot open file\n");
        return;
    }
    this->file_stream = new FileStream(this->file);
}
#endif

BaseSegment::~BaseSegment() {
	log(lsDEBUG, "IDAN BaseSegment DTOR this=%llu", (uint64_t)this);
	if (this->kv_output)
		delete this->kv_output;

    if (this->in_mem_data != NULL) {
        delete this->in_mem_data;
        this->in_mem_data = NULL;
    }

    if (this->temp_kv != NULL) {
        free(this->temp_kv);
    }
}

Segment::~Segment() {

#if 0
    if (this->file_stream != NULL) {
        delete this->file_stream;
        fclose(this->file);
        remove(this->path.c_str());
    }
#endif

}



int BaseSegment::nextKVInternal(InStream *stream) {
	//TODO: this can only work with ((DataStream*)stream)

	mem_desc_t *cur_buf = kv_output->mop_bufs[kv_output->staging_mem_idx];
	int total_read = 0;
	if (!stream){
		return 0;
	}
    
    int digested = 0;
    /* key length */

    bool k = StreamUtility::deserializeInt(*stream, cur_key_len, &kbytes);
	if (!k){
		return -1;
	}

    digested += kbytes;

    /* value length */
    bool v = StreamUtility::deserializeInt(*stream, cur_val_len, &vbytes);
    if (!v) {
        stream->rewind(digested);
        return -1;
    }
    digested += vbytes;
	if (cur_key_len == EOF_MARKER && cur_val_len == EOF_MARKER) {
        eof = true;
        total_read = kbytes + vbytes;
        byte_read += total_read;
        cur_buf->incStart(total_read);
        return 0;
    }

    /* Making a sanity check */
    if (cur_key_len < 0 || cur_val_len < 0) {
		output_stderr("Reader:Error in nextKV");
		eof = true;
		total_read = kbytes + vbytes;
		byte_read += total_read;
		cur_buf->incStart(total_read);
        return 0;
    }

    /* no enough for key + val */
    if (!stream->hasMore(cur_key_len + cur_val_len)) {
    	stream->rewind(digested);
        return -1;
    }

    int   pos = -1;
    char *mem = NULL;

    /* key */
    pos = ((DataStream*)stream)->getPosition();
    mem = ((DataStream*)stream)->getData();
    this->key.reset(mem + pos, cur_key_len);
    stream->skip(cur_key_len);

    /* val */
    pos = ((DataStream*)stream)->getPosition();
    mem = ((DataStream*)stream)->getData();
    this->val.reset(mem + pos, cur_val_len);
    stream->skip(cur_val_len);
    total_read = kbytes + vbytes + cur_key_len + cur_val_len;
    byte_read += total_read;
    cur_buf->incStart(total_read);
    return 1;

}

int BaseSegment::nextKV() {
    kbytes = vbytes = 0;

    /* in mem map output */
	if (kv_output != NULL) {
		if (eof || byte_read >= this->kv_output->total_len_raw) {
			log(lsERROR, "Reader: End of Stream [%p]- byte_read=%lld total_len=%lld", kv_output->mop_bufs[kv_output->staging_mem_idx], byte_read,  this->kv_output->total_len_raw);
	        return 0;
	    }
    	return nextKVInternal(in_mem_data);

    } else { //on-disk map output
#if 0        
        StreamUtility::deserializeInt(*file_stream, cur_key_len);
        StreamUtility::deserializeInt(*file_stream, cur_val_len);
        kbytes = StreamUtility::getVIntSize(cur_key_len);
		vbytes = StreamUtility::getVIntSize(cur_val_len);

        if (cur_key_len == EOF_MARKER
            && cur_val_len == EOF_MARKER) {
            eof = true;
            return 0;
		}
        int32_t total = cur_key_len + cur_val_len;

        if (temp_kv == NULL) {
           /* Allocating enough memory to avoid repeated use of malloc */
           temp_kv_len = total << 1;
           temp_kv = (char *) malloc(temp_kv_len * sizeof(char));
		} else {
            if (temp_kv_len < total) {
                free(temp_kv);
                temp_kv_len = total << 1;
                temp_kv= (char *) malloc(temp_kv_len * sizeof(char));
            }
        }
        file_stream->read(temp_kv, total);
        key.reset(temp_kv, cur_key_len);
        val.reset(temp_kv + cur_key_len, cur_val_len);
        return 1;
#endif
    }
    return 0;
}


void BaseSegment::close() {
    if (this->in_mem_data != NULL) {
        this->in_mem_data->close();
        delete this->in_mem_data;
        this->in_mem_data = NULL;
	}
}

void Segment::send_request() {
	//compression is not calling this function: chekcing only total_fetched_raw
	if (map_output->total_fetched_raw == map_output->total_len_part) {
		return; // TODO: probably the segment was switched while it was already reached the total_len
	} else if (map_output->total_fetched_raw > map_output->total_len_part) {
		log(lsERROR, "Unexpectedly send_request called while total_fetched_raw(%lld) >  total_len(%lld)", map_output->total_fetched_raw, map_output->total_len_part);
        return;
    }

	/* switch to new staging buffer */
    pthread_mutex_lock(&map_output->lock);
	map_output->staging_mem_idx = (map_output->staging_mem_idx == 0 ? 1 : 0);
    map_output->mop_bufs[map_output->staging_mem_idx]->status = FETCH_READY;
    map_output->fetch_count++;

    /* write_log(map_output->task->reduce_log, DBG_CLIENT,
              "Segment: mapid(%d), fetched_round(%ld), fetched_len(%ld)",
              map_output->mop_id,
              map_output->fetch_count,
              map_output->total_fetched); */
    pthread_mutex_unlock(&map_output->lock);
    map_output->task->merge_man->start_fetch_req(map_output->part_req);
}

//this function is used for compression: it sync's the DataStream in_mem_data with the cyclic buffer ('staging_mem')
bool BaseSegment::reset_data() {;
		if (kv_output != NULL) {
			mem_desc_t *staging_mem =
					kv_output->mop_bufs[kv_output->staging_mem_idx];

			int32_t	end = staging_mem->end; // no need for lock as long as we refer to same 'end' value
			int difference = end - staging_mem->start;
			if (difference < 0) {
				//checking if there is more than one key-value pair before the end of the buffer
				if (this->in_mem_data->getLength()-this->in_mem_data->getPosition() < staging_mem->buf_len-staging_mem->start){
					log(lsDEBUG, " before turnaround of the cyclic buffer [%p]. new data was added so don't have to do join start=%d end=%d count=%d pos=%d size=%d",
							staging_mem, staging_mem->start, end, this->in_mem_data->getLength(), this->in_mem_data->getPosition(), staging_mem->buf_len);
					//just reset
					this->in_mem_data->reset(staging_mem->buff+staging_mem->start, staging_mem->buf_len-staging_mem->start);
					log(lsDEBUG, " after turnaround of the cyclic buffer [%p]. new data was added so don't have to do join start=%d end=%d count=%d pos=%d size=%d",
							staging_mem, staging_mem->start, end, this->in_mem_data->getLength(), this->in_mem_data->getPosition(), staging_mem->buf_len);
					return true;
				}else{
					//indicates that there should be join
					log(lsDEBUG, "reset_data return false, cyclic buffer [%p]", staging_mem);
					return false;
				}
			}
			else {
				if (this->in_mem_data->getLength()-this->in_mem_data->getPosition() < difference){
					//there is new data
					log(lsDEBUG, "since last time more data was fetched/decompressed. resetting cyclic buffer [%p] to start=%d end=%d count=%d pos=%d",
							staging_mem, staging_mem->start, end, this->in_mem_data->getLength(), this->in_mem_data->getPosition());
					this->in_mem_data->reset(staging_mem->buff+staging_mem->start, end-staging_mem->start);
					return true;
				}
				else{
					//no new data was added: must sleep
					log(lsDEBUG, "there is no data in cyclic buffer [%p]: wait for fetch. start=%d, end=%d, count=%d, pos=%d. total_len_part is %d",
							staging_mem, staging_mem->start, end, this->in_mem_data->getLength(), this->in_mem_data->getPosition(), this->kv_output->total_len_part);

					MapOutput *mop = dynamic_cast<MapOutput*>(kv_output);
					get_task()->client->start_fetch_req(mop->part_req, NULL, 1);

					pthread_mutex_lock(&kv_output->lock);
					end = staging_mem->end;
					difference = end - staging_mem->start;
					if (this->in_mem_data->getLength()- this->in_mem_data->getPosition() >= difference) {
						// DEBUG!!!
						log(lsERROR, "going to sleep mop id=%d",mop->mop_id);
						// DEBUG!!!
						pthread_cond_wait(&kv_output->cond, &kv_output->lock);
					}
					pthread_mutex_unlock(&kv_output->lock);
					log(lsERROR, "after wait for fetch");
					return true;
				}
			}

		}

    return false;
}




//called by adjustPriorityQueue
bool BaseSegment::switch_mem() {

	if (kv_output != NULL) {
		mem_desc_t *staging_mem =
				kv_output->mop_bufs[kv_output->staging_mem_idx];

		if (byte_read >= kv_output->total_len_raw) {
			return false;
		}

		time_t st, ed;
		time(&st);
		pthread_mutex_lock(&kv_output->lock);
		//pthread_mutex_lock(&merger->lock);
		//if (staging_mem->status != MERGE_READY) {
		while (staging_mem->status != MERGE_READY) {
			pthread_cond_wait(&kv_output->cond, &kv_output->lock);
			//pthread_cond_wait(&merger->cond, &merger->lock);
			/* merger->fetched_mops.clear(); */
		}
		//pthread_mutex_unlock(&merger->lock);
		pthread_mutex_unlock(&kv_output->lock);
		time(&ed);

		kv_output->task->total_wait_mem_time += ((int) (ed - st));

		if (this->get_task()->isCompressionOn()) {
			int32_t	end = staging_mem->end; // no need for lock as long as we refer to same 'end' value
			//there is a partial key-value pair: must do join
			int32_t tempByte_read = byte_read;
			bool b = join(staging_mem->buff, end);
			staging_mem->incStart(byte_read-tempByte_read);
			return b;
		}
		else{
			// restore break record
			log(lsTRACE, "IDAN before join: total_fetched=%lld last_fetched=%lld", kv_output->total_fetched_raw, kv_output->last_fetched);
			bool b = join(staging_mem->buff, kv_output->last_fetched);
			// to check if we need more data from map output
			this->send_request();
			return b;
		}

	}

	return false;
}

bool BaseSegment::join(char *src, const int32_t src_len) {
	int index = -1;
    kbytes = vbytes = 0;

	StreamUtility::deserializeInt(*in_mem_data, cur_key_len, src, src_len,
			index, &kbytes);

    /* break in the key len */
    if (index > 0) {
        in_mem_data->reset(src + index, src_len - index);
        StreamUtility::deserializeInt(*in_mem_data, cur_val_len, &vbytes);
    } else {
		StreamUtility::deserializeInt(*in_mem_data, cur_val_len, src, src_len,
				index, &vbytes);

        /* break in the val len */
        if (index > 0) {
			in_mem_data->reset(src + index, src_len - index);
        }
    }
	if (cur_key_len == EOF_MARKER && cur_val_len == EOF_MARKER) {
        eof = true;
        byte_read += (kbytes + vbytes);
        return false;
    }

    if (index > 0) {
        /* mem has been reset */
        int   pos = -1;
        char *mem = NULL;
        pos = in_mem_data->getPosition();
        mem = in_mem_data->getData();
        key.reset(mem + pos,  cur_key_len);
        val.reset(mem + pos + cur_key_len, cur_val_len);
        in_mem_data->skip(cur_key_len + cur_val_len);
        byte_read += (kbytes + vbytes + cur_key_len + cur_val_len);
        return true;
    } else {
        /* To have a break in the middle of key or value */
        int total_len = cur_key_len + cur_val_len;
        /* DBGPRINT(DBG_CLIENT, "Reader: TOTAL-LEN = %d\n", total_len); */

        if (!temp_kv) {
            temp_kv_len = total_len << 1;
            temp_kv = (char *) malloc(temp_kv_len * sizeof(char));
            memset(temp_kv, 0, temp_kv_len);
        } else {
            if (temp_kv_len < total_len) {
                free(temp_kv);
                temp_kv_len = total_len << 1;
                temp_kv = (char *) malloc(temp_kv_len * sizeof(char));
                memset(temp_kv, 0, temp_kv_len);
            }
        }

        int part_len = in_mem_data->getLength() - in_mem_data->getPosition();

        int shift_len = (total_len - part_len);
		char *org = in_mem_data->getData() + in_mem_data->getPosition();
        /* Copying from the old partition */
        memcpy(temp_kv, org, part_len);
        /* Copying from the new partition */
        memcpy(temp_kv + part_len, src, shift_len);
        in_mem_data->reset(src + shift_len, src_len - shift_len);
        key.reset(temp_kv, cur_key_len);
        val.reset(temp_kv + cur_key_len, cur_val_len);
        byte_read += (kbytes + vbytes + cur_key_len + cur_val_len);
        return true;
	}
    return false;
}


#if LCOV_HYBRID_MERGE_DEAD_CODE

void merge_lpq_to_aio_file(reduce_task* task, MergeQueue<BaseSegment*> *records,
		const char *file_name, AIOHandler* aio, int32_t &total_write,
		int32_t& mem_desc_idx) {

	int fd = open(file_name, O_DIRECT | O_RDWR | O_TRUNC | O_CREAT);
	if (fd < 0) {
		log(lsFATAL, "Fail to open file %s\t(errno=%m)",file_name);
		exit(-1); //TODO
	}

	bool finish = false;
	uint64_t fileOffset=0;
	int prevAlignment = 0;
	int currAlignment = 0;
	int sizeToWrite = 0;
	char *aligmentTmpBuff = new char[AIO_ALIGNMENT];

	while (!finish) {
		mem_desc_t *desc = records->staging_bufs[mem_desc_idx];

		pthread_mutex_lock(&desc->lock);
		while ((desc->status != FETCH_READY) && (desc->status != INIT))
		pthread_cond_wait(&desc->cond, &desc->lock);
		pthread_mutex_unlock(&desc->lock);

		// copy previous alignment carry data from tmp buffer to the begining of current staging buffer
		if (prevAlignment) {
			memcpy((void*)desc->buff, (void*)aligmentTmpBuff, prevAlignment);
		}

		log(lsDEBUG, "calling write_kv_to_mem desc->buf_len=%d", desc->buf_len);
		finish = write_kv_to_mem(records,
				desc->buff + prevAlignment,
				desc->buf_len - prevAlignment,
				desc->act_len);

		desc->status = MERGE_READY;
		currAlignment = (desc->act_len + prevAlignment) % AIO_ALIGNMENT;
		sizeToWrite = (desc->act_len + prevAlignment) - currAlignment;
		// copy new alignment carry data to tmp buffer for next time to be written
		if (currAlignment)
		memcpy((void*)aligmentTmpBuff, (void*)(desc->buff + sizeToWrite), currAlignment);

		// fileOffset, size and buffPTR must be aligned for AIO
		lpq_aio_arg_t* arg = new lpq_aio_arg_t();
		arg->desc=desc;
		arg->fd = fd;
		arg->filename=file_name; // reopening the file without O_DIRECT to enabling lseak on fd in order to write the last unaligned curry blocking.
		if (finish) {
			// callback for the last aio write will write the last alignment carry ,close the fd and delete aligment_buff
			arg->last_lpq_submition=true;
			arg->aligment_carry_size=currAlignment;
			arg->aligment_carry_buff=aligmentTmpBuff;
			arg->aligment_carry_fileOffset=fileOffset+sizeToWrite;
		}
		else {
			arg->last_lpq_submition=false;
			arg->aligment_carry_size=0;
			arg->aligment_carry_buff=NULL;
			arg->aligment_carry_fileOffset=0;
		}
		log(lsTRACE, "IDAN_LPQ_AIO prepeare_write:  fd=%d fileOffset=%llu act_len=%d prevAlignment=%d currAlignment=%d sizeToWrite=%d", fd, fileOffset, desc->act_len, prevAlignment, currAlignment, sizeToWrite );
		aio->prepare_write(fd, fileOffset, sizeToWrite , desc->buff, arg );
		aio->submit(); //TODO : batch
		fileOffset += sizeToWrite;
		prevAlignment=currAlignment;

		++mem_desc_idx;
		if (mem_desc_idx >= NUM_STAGE_MEM) {
			mem_desc_idx = 0;
		}

	}
}

AioSegment::AioSegment(KVOutput* kvOutput, AIOHandler* aio,
	const char* filename) :
	BaseSegment(kvOutput) {
	log(lsDEBUG, "IDAN AioSegment CTOR this=%llu , filename=%s", (uint64_t)this, filename);
	this->aio = aio;
	this->fd = open(filename, O_DIRECT | O_RDONLY);
	if (this->fd < 0) {
		log(lsERROR, "cannot open file: %s - %m", filename);
	}
	else
	{
		struct stat st;
		fstat(fd, &st);
		this->kv_output->total_len = st.st_size;
		log(lsTRACE, "IDAN lpq output file %s is open - size=%lld", filename, st.st_size)

		log(lsDEBUG, "IDAN AioSegment CTOR finish this=%llu , filename=%s", (uint64_t)this, filename);
	}
}

void AioSegment::send_request() {
	int rc;
	log(lsTRACE, " IDAN ENTERED func  - total_len=%lld , total_fetched=%lld", kv_output->total_len , kv_output->total_fetched);
	if (kv_output->total_fetched > kv_output->total_len) {
		log(lsERROR, "Unexpectedly send_request called while total_fetched(%lld) >  total_len(%lld)", kv_output->total_fetched, kv_output->total_len);
	}
	else if (kv_output->total_fetched < kv_output->total_len) {
		/* switch to new staging buffer */
		pthread_mutex_lock(&kv_output->lock);
		if (this->kv_output->total_fetched > 0) // not the first request
			kv_output->staging_mem_idx = (kv_output->staging_mem_idx == 0 ? 1 : 0);
		mem_desc_t* desc = kv_output->mop_bufs[kv_output->staging_mem_idx];
		desc->status = BUSY;
		pthread_mutex_unlock(&kv_output->lock);

		// submit aio read request
		rpq_aio_arg* arg = new rpq_aio_arg();
		arg->desc = desc;
		arg->kv_output = this->kv_output;
		arg->segment=this;
		arg->size = kv_output->total_len - kv_output->total_fetched;
		if (arg->size > desc->buf_len)
			arg->size = desc->buf_len;

		int alignment = (arg->size % AIO_ALIGNMENT);
		if (alignment)
			alignment = AIO_ALIGNMENT - (arg->size % AIO_ALIGNMENT);

		log(lsTRACE, "RPQ AIO READ REQUEST: fd=%d, total_fetched=%lld size=%llu (AIO write size = %d) ",this->fd, kv_output->total_fetched, arg->size, arg->size + alignment);
		if (aio->prepare_read(this->fd, kv_output->total_fetched, arg->size + alignment, desc->buff, arg)) {
			log(lsERROR, "Fail to prepeare aio read request for fd=%d, fileoffset=%ll, size=%llu", this->fd, kv_output->total_fetched, arg->size);
		} else {
			rc = aio->submit();
			if (rc == 0) {
				log(lsTRACE, "IDAN_SEND_REQ_AIO_SUBMIT returned with 0 submitted requests after preparing the req: fd=%d, total_fetched=%ll size=%llu (for AIO buffer len - %d) ",this->fd, kv_output->total_fetched, arg->size, desc->buf_len);
			}
			else if (rc < 0) {
				log(lsERROR, "aio submit failed with rc=%d - %m  - after prepearing the req: fd=%d, total_fetched=%ll size=%llu (for AIO buffer len - %d) ",this->fd, kv_output->total_fetched, arg->size, desc->buf_len);
			}
		}
	}
	//else  (kv_output->total_fetched == kv_output->total_len) {

}

AioSegment::~AioSegment() {
	::close(this->fd);
	log(lsDEBUG, "IDAN AioSegment DTOR this=%llu", (uint64_t)this)
;}

SuperSegment::SuperSegment(reduce_task *_task, const std::string &_path) :
	Segment(NULL), task(_task), path(_path) {
    this->file = fopen(path.c_str(), "rb");
    if (this->file == NULL) {
		output_stderr("Reader:cannot open file: %s", path.c_str())
;		this->file_stream = NULL;
        return;
    }
    this->file_stream = new FileStream(this->file);
}

SuperSegment::~SuperSegment() {
    if (this->file_stream != NULL) {
        delete this->file_stream;
        fclose(this->file);
        remove(this->path.c_str());
    }
}


int SuperSegment::nextKV() {
	int dummy;
    StreamUtility::deserializeInt(*file_stream, cur_key_len, &dummy);//AVNER: TODO
    StreamUtility::deserializeInt(*file_stream, cur_val_len, &dummy);
    kbytes = StreamUtility::getVIntSize(cur_key_len);
    vbytes = StreamUtility::getVIntSize(cur_val_len);

	if (cur_key_len == EOF_MARKER && cur_val_len == EOF_MARKER) {
        eof = true;
        return 0;
    }
    int32_t total = cur_key_len + cur_val_len;

    if (temp_kv == NULL) {
       /* Allocating enough memory to avoid repeated use of malloc */
       temp_kv_len = total << 1;
       temp_kv = (char *) malloc(temp_kv_len * sizeof(char));
    } else {
        if (temp_kv_len < total) {
            free(temp_kv);
            temp_kv_len = total << 1;
			temp_kv = (char *) malloc(temp_kv_len * sizeof(char));
        }
    }
    file_stream->read(temp_kv, total);
    key.reset(temp_kv, cur_key_len);
    val.reset(temp_kv + cur_key_len, cur_val_len);
    return 1;
}

#endif

#if LCOV_AUBURN_DEAD_CODE
bool write_kv_to_file(MergeQueue<BaseSegment*> *records, FILE *f,
		int32_t &total_write) {
    FileStream *stream = new FileStream(f);
    int32_t len = INT32_MAX; //1<<30; //TODO: consider 64 bit - AVNER

    bool ret = write_kv_to_stream(records, len, stream, total_write);

    stream->flush();
    delete stream;
    return ret;
}

bool write_kv_to_file(MergeQueue<BaseSegment*> *records, const char *file_name,
		int32_t &total_write) {
    FILE *file = fopen(file_name, "wb");
    if (!file) {
    	log(lsFATAL, "[pid=%d] fail to open file(errno=%d: %m)\n", getpid(), errno);
    	exit(-1); //temp TODO
    }

    bool ret = write_kv_to_file(records, file, total_write);

    fclose(file);
    return ret;
}
#endif





/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
