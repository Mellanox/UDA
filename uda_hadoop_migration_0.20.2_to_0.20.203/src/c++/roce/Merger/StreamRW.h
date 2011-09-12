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
class MergeQueue;

/* The following is for class Segment */
class Segment
{
public:
    Segment (MapOutput *mapOutput);
    /* Segment (const std::string &path); */
    ~Segment();

    /**
     *-1: data interruption;
     * 0: no more data, end of the map output;
     * 1: next key/value exits;
     *
     * if there is an interruption, the current point need to rewind to 
     * the original position
     */ 
    int         nextKV();
    bool        join (char *src, int32_t src_len);
    bool        switch_mem();
    void        close();
    void        send_request();

    DataStream  key;
    DataStream  val;

    MapOutput   *map_output; 
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

bool write_kv_to_mem (MergeQueue *records, char *src,
                      int32_t len, int32_t &total_write);
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
