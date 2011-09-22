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

#define EOF_MARKER (-1)

#include <stdio.h>
#include <map>
#include <ctime>
#include <sys/stat.h>

#include "MergeManager.h"
#include "MergeQueue.h"
#include "StreamRW.h"
#include "IOUtility.h"
#include "reducer.h"

using namespace std;

bool write_kv_to_mem(MergeQueue *records, 
                     char *src, int32_t len, int32_t &total_write) 
{
    int32_t key_len, val_len, bytes_write;
    int32_t kbytes, vbytes;
    int32_t record_len;

    bytes_write = 0;
    key_len = val_len = kbytes = vbytes = 0;

    DataStream *stream = new DataStream(src, len);
   
    while (records->next()) {
        DataStream *k = records->getKey();
        DataStream *v = records->getVal();
    
        key_len = records->get_key_len(); 
        val_len = records->get_val_len(); 

        if (key_len < 0 || val_len < 0) {
            output_stderr("key_len or val_len < 0");
            return true;
        }
   
        /* check if the entire <k,v> can be written into mem */ 
        kbytes = records->get_key_bytes();
        vbytes = records->get_val_bytes();

        record_len = kbytes + vbytes + key_len + val_len;
        if ( record_len + bytes_write > len ) {
            total_write = bytes_write;
            records->mergeq_flag = 1;
            return false;
        }

        StreamUtility::serializeInt(key_len, *stream);
        StreamUtility::serializeInt(val_len, *stream);
        stream->write(k->getData(), key_len);
        stream->write(v->getData(), val_len);
        bytes_write += record_len;
        records->mergeq_flag   = 0;
    }
   
    /* test for last -1, -1 */ 
    kbytes = StreamUtility::getVIntSize(EOF_MARKER); 
    vbytes = StreamUtility::getVIntSize(EOF_MARKER);
    record_len = kbytes + vbytes;
    if (record_len + bytes_write > len) {
        total_write = bytes_write;
        records->mergeq_flag   = 1;
        return false;
    }
    
    /* -1:-1 */
    StreamUtility::serializeInt(EOF_MARKER, *stream);
    StreamUtility::serializeInt(EOF_MARKER, *stream);
    delete stream;
    records->mergeq_flag = 0;
    bytes_write += record_len;  
   
    total_write = bytes_write; 
    return true;
}

#if 0
void write_kv_to_disk(RawKeyValueIterator *records, const char *file_name)
{
    int32_t key_len, val_len;
    FILE *file = fopen(file_name, "wb");
    if (!file) {
        fprintf(stderr, "[%d:%s:%d] fail to open file\n",
                getpid(), __FILE__, __LINE__);
    }
    FileStream *stream = new FileStream(file);

    while (records->next()) {
        DataStream *k = records->getKey();
        DataStream *v = records->getVal();
    
        key_len = k->getLength() - k->getPosition(); 
        val_len = v->getLength() - v->getPosition(); 
        if (key_len < 0 || val_len < 0) {
            fprintf(stderr, "key_len or val_len < 0\n");
        }
    
        StreamUtility::serializeInt(key_len, *stream);
        StreamUtility::serializeInt(val_len, *stream);
        stream->write(k->getData(), key_len);
        stream->write(v->getData(), val_len);
    }

    fclose(file);
    delete stream;
}
#endif

/*  The following is for class Segment */
Segment::Segment(MapOutput *mapOutput)
{
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

    this->map_output = mapOutput;
    mem_desc_t *mem = 
        mapOutput->mop_bufs[mapOutput->staging_mem_idx]; 
   
    this->in_mem_data = new DataStream();
    this->in_mem_data->reset(mem->buff, 
                  mapOutput->part_req->last_fetched);
    this->send_request();
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

Segment::~Segment()
{
    int id = this->map_output->mop_id;
    reduce_task_t *task = 
        this->map_output->task;

    if (this->map_output != NULL) {
        delete this->map_output;
    }
    
    if (this->in_mem_data != NULL) {
        delete this->in_mem_data;
        this->in_mem_data = NULL;
    }
    
    if (this->temp_kv != NULL) {
        free(this->temp_kv);
    }

#if 0
    if (this->file_stream != NULL) {
        delete this->file_stream;
        fclose(this->file);
        remove(this->path.c_str());
    }
#endif

    write_log(task->reduce_log,DBG_CLIENT, 
              "Segment %d: deleted", id);
}

int Segment::nextKV()
{
    int digested;
    kbytes = vbytes = digested = 0;

    if (eof || byte_read >= this->map_output->total_len) {
        output_stderr("Reader: End of Stream");
        return 0;
    }
    
    /* in mem map output */
    if (map_output != NULL) {
        
        if (!in_mem_data) return 0;

        /* key length */
        bool k = StreamUtility::deserializeInt(*in_mem_data, cur_key_len, &kbytes);
        if (!k)  return -1; 
        digested += kbytes;

        /* value length */
        bool v = StreamUtility::deserializeInt(*in_mem_data, cur_val_len, &vbytes);
        if (!v) {
            this->in_mem_data->rewind(digested);
            return -1;
        }
        digested += vbytes;

        if (cur_key_len == EOF_MARKER 
         && cur_val_len == EOF_MARKER) {
            eof = true;
            byte_read += (kbytes + vbytes);
            return 0;
        }

        /* Making a sanity check */
        if (cur_key_len < 0 || cur_val_len < 0) {
            output_stderr("Reader:Error in nextKV");
            eof = true;
            byte_read += (kbytes + vbytes);
            return 0;
        }
        
        /* no enough for key + val */
        if (!in_mem_data->hasMore(cur_key_len + cur_val_len)) {
            in_mem_data->rewind(digested);
            return -1;
        }
  
        int   pos = -1;
        char *mem = NULL;

        /* key */
        pos = in_mem_data->getPosition();
        mem = in_mem_data->getData();
        this->key.reset(mem + pos, cur_key_len);
        in_mem_data->skip(cur_key_len); 

        /* val */
        pos = in_mem_data->getPosition();
        mem = in_mem_data->getData();
        this->val.reset(mem + pos, cur_val_len);
        in_mem_data->skip(cur_val_len);
        byte_read += (kbytes + vbytes + cur_key_len + cur_val_len);
        return 1;

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

void Segment::close()
{ 
    if (this->in_mem_data != NULL) {
        this->in_mem_data->close();
        delete this->in_mem_data;
        this->in_mem_data = NULL;
    } 
}


void Segment::send_request()
{
    if (map_output->total_fetched >= map_output->total_len) {
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

    pthread_mutex_lock(&map_output->task->fetch_man->send_lock);
    map_output->task->fetch_man->fetch_list.push_back(map_output->part_req);
    pthread_cond_broadcast(&map_output->task->fetch_man->send_cond);
    pthread_mutex_unlock(&map_output->task->fetch_man->send_lock);
}

bool Segment::switch_mem() 
{
    if (map_output != NULL) {
        mem_desc_t *staging_mem = 
            map_output->mop_bufs[map_output->staging_mem_idx];

        if (byte_read >= map_output->total_len) {
            return false;
        }

        MergeManager *merger = map_output->task->merge_man;

        time_t st, ed;
        time(&st);
        //pthread_mutex_lock(&map_output->lock);
        pthread_mutex_lock(&merger->lock);
        //if (staging_mem->status != MERGE_READY) {
        while (staging_mem->status != MERGE_READY) {
            //pthread_cond_wait(&map_output->cond, &map_output->lock);
            pthread_cond_wait(&merger->cond,
                              &merger->lock);
            merger->fetched_mops.clear();
        }
        pthread_mutex_unlock(&merger->lock);
        //pthread_mutex_unlock(&map_output->lock);
        time(&ed);

        map_output->task->total_wait_mem_time += ((int)(ed - st));

        /* restore break record */ 
        bool b = join(staging_mem->buff, map_output->part_req->last_fetched);
        
        /* to check if we need more data from map output*/
        this->send_request();
        return b;
    }
    return false;
}

bool Segment::join(char *src, const int32_t src_len ) 
{
    int index = -1; 
    kbytes = vbytes = 0;

    StreamUtility::deserializeInt(*in_mem_data, cur_key_len,
                                  src, src_len, index, &kbytes);

    /* break in the key len */
    if (index > 0) {
        in_mem_data->reset(src + index, src_len - index);
        StreamUtility::deserializeInt(*in_mem_data, cur_val_len, &vbytes);
    } else {
        StreamUtility::deserializeInt(*in_mem_data, cur_val_len,
                                      src, src_len, index, &vbytes);

        /* break in the val len */
        if (index > 0) {
            in_mem_data->reset(src+index, src_len - index);
        }
    }
    if (cur_key_len == EOF_MARKER
     && cur_val_len == EOF_MARKER) {
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
        /* DBGPRINT(DBG_CLIENT, "Reader: PART-LEN  = %d\n", part_len); */

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

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
