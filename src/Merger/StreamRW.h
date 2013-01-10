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

#ifndef _STREAM_READ_WRITE_H
#define _STREAM_READ_WRITE_H

#include <string>

#include "IOUtility.h"
#include "NetlevComm.h"

class MapOutput;
class RawKeyValueIterator;
#include "MergeQueue.h"
#include "AIOHandler.h"
#include "CompareFunc.h"

class BaseSegment
{
public:
    BaseSegment (KVOutput *kvOutput);
    /* Segment (const std::string &path); */
    virtual ~BaseSegment();

    /**
     *-1: data interruption;
     * 0: no more data, end of the map output;
     * 1: next key/value exits;
     *
     * if there is an interruption, the current point need to rewind to 
     * the original position
     */ 
    virtual int         nextKV();
    virtual bool        switch_mem();
    virtual void        close();
    virtual void        send_request() = 0;
    virtual reduce_task *get_task() {return kv_output->task;}

    bool operator<(BaseSegment &seg) { 	return ( (g_cmp_func(key.getData(), key.getLength(), seg.key.getData(), seg.key.getLength())) < 0 ); }

    DataStream  key;
    DataStream  val;
protected:
    virtual int         nextKVInternal(InStream *stream);
    virtual bool        join (char *src, int32_t src_len);

    KVOutput   *kv_output;
public:
    int32_t      cur_key_len;
    int32_t      cur_val_len;
    int32_t      kbytes;
    int32_t      vbytes;
    bool         eof;
    char        *temp_kv; 
    int32_t      temp_kv_len;
    char        *temp_buf;
    int32_t      temp_buf_len;
    int64_t      byte_read;
    DataStream  *in_mem_data;
};
	

/* The following is for class Segment */
class Segment : public BaseSegment
{
public:
    Segment (MapOutput *mapOutput);
    /* Segment (const std::string &path); */
    virtual ~Segment();

    virtual void        send_request();

protected:
    MapOutput   *map_output;
#if 0
    FILE        *file;
    FileStream  *file_stream;
    std::string  path;
#endif
};





bool write_kv_to_mem (MergeQueue<BaseSegment*> *records, char *src,
                      int32_t len, int32_t &total_write);

bool write_kv_to_file(MergeQueue<BaseSegment*> *records, const char *file_name, int32_t &total_write);

void write_kv_to_disk(RawKeyValueIterator *records, const char *file_name);

void merge_lpq_to_aio_file(reduce_task* task, MergeQueue<BaseSegment*> *records, const char *file_name, AIOHandler* aio, int32_t &total_write, int32_t& mem_desc_idx);


#endif

#if LCOV_HYBRID_MERGE_DEAD_CODE
/* The following is for class SuperSegment */
//
// SuperSegment is built of several Segments that were all merged into one
// big Segment.
// I could name it FileSegment, since currently it is simply a Segment that
// is taken from local file.  However, SuperSegment is better name, since we
// may create it over memory in the future.
//
class SuperSegment : public Segment
{
public:
	SuperSegment (reduce_task *_task, const std::string &_path);
    /* SuperSegment (const std::string &path); */
    ~SuperSegment();

    /**
     *-1: data interruption;
     * 0: no more data, end of the map output;
     * 1: next key/value exits;
     *
     * if there is an interruption, the current point need to rewind to
     * the original position
     */
    virtual int  nextKV();
    virtual bool join (char *src, int32_t src_len){log(lsERROR, "shouldn't reach here"); throw new UdaException("shouldn't reach here"); return true;}
    virtual bool switch_mem() {log(lsERROR, "shouldn't reach here"); throw new UdaException("shouldn't reach here"); return true;}

    virtual void close() {return this->Segment::close();}
//    virtual void send_request() {} // nothing to do in derived class
    virtual void send_request() {log(lsERROR, "shouldn't reach here"); throw new UdaException("shouldn't reach here");}
    virtual reduce_task *get_task() {return task;}

    reduce_task *task;

    FILE        *file;
    FileStream  *file_stream;
    std::string  path;
};

class AioSegment : public BaseSegment {
protected:
	AIOHandler* aio;
	int			fd;
public:
	AioSegment(KVOutput* kvOutput, AIOHandler* aio, const char* filename);
	~AioSegment();
	virtual void send_request();
};
#endif


/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
