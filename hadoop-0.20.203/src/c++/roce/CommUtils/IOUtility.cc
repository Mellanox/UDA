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

#include <errno.h>
#include <stdarg.h>
#include <time.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/socket.h>

#include "IOUtility.h"


using namespace std;

/* FileStream class */
NetStream::NetStream(int socket)
{
    this->socket = socket;
}

size_t NetStream::read(void *buf, size_t len)
{ 
    size_t result = recv(socket, buf, len, 0); 
    if (result == -1) {
        output_stderr("NetStream: recv error, %s",
                      strerror(errno));
    }
    return result;
}


size_t NetStream::write(const void *buf, size_t len)
{
    size_t result = send(socket, buf, len, 0);
    if (result == -1) {
        output_stderr("NetStream: send error, %s",
                      strerror(errno));
        return 0;
    }
    return result;
}

/* DataStream class */
DataStream::DataStream()
{
    this->buf  = NULL;
    this->count= 0;
    this->pos  = 0;
}

DataStream::DataStream(char *buf, int32_t len)
{
    this->buf  = buf;
    this->pos  = 0;
    this->count= len;
}


DataStream::~DataStream()
{
}

void DataStream::reset(char *input, int start, int len)
{
    this->buf   = input;
    this->count = start + len;
    this->pos   = start;
}

void DataStream::reset(char *input, int len)
{
    reset(input, 0, len);
}

size_t DataStream::read(void *des, const size_t len, 
                        const char *extrasrc, size_t size, int &idx)
{
    if (len < 0 || size < 0) { 
        output_stderr("DataStream: len or size < 0");
        return -1;
    }
    if ((this->pos + len) <= this->count) {
        memcpy(des, (this->buf + this->pos), len);
        this->pos += len;
        return len;
    } 
    size_t a = this->count - this->pos;
    memcpy(des, (this->buf + this->pos), a);
    idx = len - a;
    memcpy(((char*)des + a), extrasrc, idx); 
    return len; 
}


size_t DataStream::read(void *des, size_t len)
{
    if (len < 0) {
        output_stderr("DataStream: len < 0");
        return -1;
    }
    if ((this->pos + len) > this->count) {
        output_stderr("DataStream: read out of bound");
        return -1;
    }
    if (len == 0) return 0;

    memcpy(des, (this->buf + this->pos), len);
    this->pos += len;
    return len;
}

size_t DataStream::rewind(size_t nbytes) 
{
    if (this->pos - nbytes < 0) {
        output_stderr("DataStream: rewind out of bound");
        return -1;
    }
    this->pos -= nbytes;
    return nbytes; 
}

size_t DataStream::skip(size_t nbytes)
{
    if (this->pos + nbytes > this->count) {
        output_stderr("DataStream: skip out of bound");
        return -1;
    }
    this->pos += nbytes;
    return nbytes;
}


bool DataStream::hasMore(size_t nbytes) 
{
    if (this->pos + nbytes > this->count) {
        return false;
    }
    return true;
}

void DataStream::flush()
{
}

bool DataStream::close()
{
    this->pos = 0;
    return true;
}

size_t DataStream::write(const void *buf, size_t len)
{
    if (len < 0) {
        output_stderr("DataStream: len < 0");
        return -1;
    }

    if (this->pos + len > this->count) {
        output_stderr("DataStream: write out of bound");
        return -1;
    }
    if (len == 0) return 0;

    /*simple memory copy*/
    memcpy( (this->buf + this->pos), buf, len );
    this->pos+=len;       
    return len; 
}


/* StreamUtility class */
void StreamUtility::serializeInt(int32_t t, OutStream& stream)
{
    serializeLong(t, stream);
}

void StreamUtility::serializeLong(int64_t t, OutStream& stream)
{
    if (t >= -112 && t <= 127) {
        int8_t b = t;
        stream.write(&b, 1);
        return;
    }

    int8_t len = -112;
    if (t < 0) {
        t ^= -1ll; // reset the sign bit
        len = -120;
    }

    uint64_t tmp = t;
    while (tmp != 0) {
        tmp = tmp >> 8;
        len--;
    }

    stream.write(&len, 1);
    len = (len < -120) ? -(len + 120) : -(len + 112);

    for (uint32_t idx = len; idx != 0; idx--) {
        uint32_t shiftbits = (idx - 1) * 8;
        uint64_t mask = 0xFFll << shiftbits;
        uint8_t b = (t & mask) >> shiftbits;
        stream.write(&b, 1);
    }
}


void StreamUtility::serializeString(const std::string& t, OutStream& stream)
{
    serializeInt(t.length(), stream);
    if (t.length() > 0) {
        stream.write(t.data(), t.length());
    }
}


bool StreamUtility::deserializeInt(InStream &stream, int32_t &ret, int *br) 
{
    int64_t t;
    bool b = deserializeLong(stream,t, br);
    if (!b) return false;
    ret = (int32_t)t;
    return b;
}

bool StreamUtility::deserializeInt(InStream &stream, int32_t &ret, 
                                   const char *extrasrc, size_t size, 
                                   int &index, int *br)
{
    int64_t t;
    bool b = deserializeLong(stream, t, extrasrc, size, index, br);
    if (!b) return false;
    ret = (int32_t)t;
    return b;
}

bool StreamUtility::deserializeLong(InStream &stream, int64_t &ret, 
                                    const char *extrasrc, size_t size, 
                                    int &index, int *br)
{
    int tempIdx = -1;
    int8_t b;
    if (-1 == stream.read(&b, 1, extrasrc, size, tempIdx)) {
        return false;
    }
    if (b >= -112) {
        ret = b;
        index = tempIdx > 0 ? tempIdx : index;
        *br = 1;
        return true;
    }
    bool negative;
    int len;
    if (b < -120) {
        negative = true;
        len = -120 - b;
    } else {
        negative = false;
        len = -112 - b;
    }
    uint8_t barr[len];
    if (tempIdx < 0) {
        if (-1 == stream.read(barr, len, extrasrc, size, tempIdx)) {
            return false;
        }
    } else {
        memcpy(barr, extrasrc + tempIdx, len);
        tempIdx += len;
    }
    int64_t t = 0;
    for (int idx = 0; idx < len; idx++) {
        t = t << 8;
        t |= (barr[idx] & 0xFF);
    }
    if (negative) {
        t ^= -1ll;
    }
    ret = t;
    index = tempIdx > 0 ? tempIdx : index;
    *br = len + 1;
    return true;
}


bool StreamUtility::deserializeLong(InStream &stream, int64_t &ret, int *br)
{
    int digested = 0;
    int8_t b;
    if (-1 == stream.read(&b, 1)) {
        return false;
    }
    digested += 1;
    if (b >= -112) {
        ret = b;
        *br = 1;
        return true;
    }
    bool negative;
    int len;
    if (b < -120) {
        negative = true;
        len = -120 - b;
    } else {
        negative = false;
        len = -112 - b;
    }
    uint8_t barr[len];
    if (-1 == stream.read(barr, len)) {
        stream.rewind(digested);
        return false;
    }
    int64_t t = 0;
    for (int idx = 0; idx < len; idx++) {
        t = t << 8;
        t |= (barr[idx] & 0xFF);
    }
    if (negative) {
        t ^= -1ll;
    }
    ret = t;
    *br = len + 1; 
    return true;
}

bool StreamUtility::deserializeString(std::string& t, InStream& stream)
{
    int32_t len;
    int br;
    bool b = deserializeInt(stream, len, &br);
    if (!b) return false;
    if (len > 0) {
        t.resize(len);
        const int bufSize = 1024;
        int offset = 0;
        char buf[bufSize];
        int digested = 0;
        while (len > 0) {
            int chunkLength = len > bufSize ? bufSize : len;
            if (-1 == stream.read(buf, chunkLength)) {
                output_stderr("deserialize string error, %s",
                              strerror(errno));
                stream.rewind(digested);
                return false;
            }
            digested += chunkLength;
            t.replace(offset, chunkLength, buf, chunkLength);
            offset += chunkLength;
            len -= chunkLength;
        }
        return true;
    } else {
        t.clear();
    }
    return false;
}

int StreamUtility::getVIntSize(int64_t i) 
{
    if (i >= -112 && i <= 127) {
        return 1;
    }
    if (i < 0) {
        i ^= -1ll;
    }
    int dataBits = 0;
    int64_t tmp = i;
    while (tmp != 0) {
        tmp >>= 1;
        ++dataBits;	
    }
    return (dataBits + 7) / 8 + 1;
}


char *rocelog_dir = "default";
const char *default_log = "default";
bool record = true;

void write_log(FILE *log, int dbg, char *fmt, ...)
{
    if (dbg && record && log != NULL) {
      time_t rawtime;
      struct tm *ti = NULL;

      time(&rawtime);
      ti = localtime(&rawtime);

      char s1[256];
      va_list ap;
      va_start(ap, fmt);
      vsprintf(s1, fmt, ap);
      va_end(ap);
      if (ti) {
        fprintf(log, "Time %d:%d:%d LOG: %s\n",
                ti->tm_hour,
                ti->tm_min,
                ti->tm_sec, s1);
      } else {
        fprintf(log, "Time is missing. LOG: %s\n", s1);
      }

      fflush(log);
    }
}

void output_stderr(char *fmt, ...) 
{
    if (!record) {
         return;
    }
      
    time_t rawtime;
    struct tm *ti = NULL;
    time(&rawtime);
    ti = localtime(&rawtime);

    char s1[256];
    va_list ap;
    va_start(ap, fmt);
    vsprintf(s1, fmt, ap);
    va_end(ap);

    if (ti) {
      fprintf(stderr, "Time %d:%d:%d  Error: %s\n", 
              ti->tm_hour,
              ti->tm_min,
              ti->tm_sec,
              s1);
    } else {
      fprintf(stderr, "Time is missing. Error: %s\n", s1);
    }
    fflush(stderr);
}

void output_stdout(char *fmt, ...) 
{
    if (!record) {
         return;
    }
    
    char s1[256];
    va_list ap;
    va_start(ap, fmt);
    vsprintf(s1, fmt, ap);
    va_end(ap);
    fprintf(stdout, "%s\n", s1);
    fflush(stdout);
}


FILE* create_log(char *log_name)
{
    char full_path[256];

    if (log_name == NULL 
     || !record) {
        return NULL;
    }

    /*log name*/
    sprintf(full_path, "%s%s", 
            rocelog_dir, log_name);
    FILE *log = fopen(full_path, "w");
    return log;
}

void close_log(FILE *log)
{
    if (log != NULL)
      fclose(log);
}

void redirect_stderr(char *proc) 
{
    char full_path[256];

    if (!record)
        return;
      
    sprintf(full_path, "%s%s.stderr", 
            rocelog_dir, proc);
    freopen (full_path,"w",stderr);
}

void redirect_stdout(char *proc)
{
    char full_path[256];
    
    if (!record)
        return;
    
    sprintf(full_path, "%s%s.stdout",
            rocelog_dir, proc);
    freopen (full_path,"w",stdout);

}

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
