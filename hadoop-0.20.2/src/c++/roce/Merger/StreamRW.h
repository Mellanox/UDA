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

#ifndef _STREAM_READ_WRITE_H
#define _STREAM_READ_WRITE_H

#include <string>

#include "IOUtility.h"
#include "NetlevComm.h"

class MapOutput;
class RawKeyValueIterator;
#include "MergeQueue.h"

/* The following is for class Segment */
class Segment
{
public:
    Segment (MapOutput *mapOutput);
    /* Segment (const std::string &path); */
    virtual ~Segment();

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
    virtual void        send_request();
    virtual reduce_task *get_task() {return map_output->task;}

    DataStream  key;
    DataStream  val;
protected:
    virtual int         nextKVInternal(InStream *stream);
    virtual bool        join (char *src, int32_t src_len);
    MapOutput   *map_output;
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
#if 0
    FILE        *file;
    FileStream  *file_stream;
    std::string  path;
#endif
};

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
    virtual bool join (char *src, int32_t src_len){output_stderr("shouldn't reach here"); throw "shouldn't reach here"; return true;} //TODO
    virtual bool switch_mem() {output_stderr("shouldn't reach here"); throw "shouldn't reach here"; return true;} //TODO

    virtual void close() {return this->Segment::close();}
//    virtual void send_request() {} // nothing to do in derived class
    virtual void send_request() {output_stderr("shouldn't reach here"); throw "shouldn't reach here";} //AVNER: TODO
    virtual reduce_task *get_task() {return task;}

    reduce_task *task;

    FILE        *file;
    FileStream  *file_stream;
    std::string  path;
};

bool write_kv_to_mem (MergeQueue<Segment*> *records, char *src,
                      int32_t len, int32_t &total_write);

bool write_kv_to_file(MergeQueue<Segment*> *records, const char *file_name, int32_t &total_write);

void write_kv_to_disk(RawKeyValueIterator *records, const char *file_name);

#endif

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
