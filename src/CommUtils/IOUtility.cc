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

#include <errno.h>
#include <stdarg.h>
#include <time.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <execinfo.h>  // for backtrace

#include <limits.h> // for PATH_MAX


#include "IOUtility.h"


using namespace std;








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
    if ((this->pos + len) > this->count) {
        log(lsERROR,"DataStream: read out of bound");
        print_backtrace("IDAN_StreamOutOfBound");
        return -1;
    }
    if (len == 0) return 0;

    memcpy(des, (this->buf + this->pos), len);
    this->pos += len;
    return len;
}

size_t DataStream::rewind(size_t nbytes) 
{
    if (this->pos < nbytes) {
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
    if ((size_t)(-1) == stream.read(&b, 1, extrasrc, size, tempIdx)) {
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
        if ((size_t)(-1) == stream.read(barr, len, extrasrc, size, tempIdx)) {
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


/**
    * Serializes a long to a binary stream with zero-compressed encoding.
    * For -112 <= i <= 127, only one byte is used with the actual value.
    * For other values of i, the first byte value indicates whether the
    * long is positive or negative, and the number of bytes that follow.
    * If the first byte value v is between -113 and -120, the following long
    * is positive, with number of bytes that follow are -(v+112).
    * If the first byte value v is between -121 and -128, the following long
    * is negative, with number of bytes that follow are -(v+120). Bytes are
    * stored in the high-non-zero-byte-first order.
    * */
bool StreamUtility::deserializeLong(InStream &stream, int64_t &ret, int *br) {
    if (!stream.hasMore(1))
       return false;

    int digested = 0;
    int8_t b;
    if ((size_t)(-1) == stream.read(&b, 1)) {
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

    if (!stream.hasMore(len)) {
    	stream.rewind(digested);
    	return false;
    }


    uint8_t barr[len];
    if ((size_t)(-1) == stream.read(barr, len)) {
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
            if ((size_t)(-1) == stream.read(buf, chunkLength)) {
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


//------------------------------------------------------------------------------
const char *rdmalog_dir = "default";
static FILE *log_file = NULL;
log_severity_t g_log_threshold = DEFAULT_LOG_THRESHOLD;

//------------------------------------------------------------------------------
void startLogNetMerger()
{
	log_file = NULL;
    char full_path[PATH_MAX];

    if (g_log_threshold <= lsNONE)
        return;

	sprintf(full_path, "%sudaNetMerger.log", rdmalog_dir);
	printf("log will go to: %s\n", full_path);
	log_file = fopen (full_path,"a");

    if (!log_file) {
        printf("log will go to stderr\n");
        fprintf(stderr, "log will go to stderr\n");
    	log_file = stderr;
    }
}


//------------------------------------------------------------------------------
void startLogMOFSupplier()
{
	log_file = NULL;
    char full_path[PATH_MAX];

	if (g_log_threshold <= lsNONE)
        return;
      
    char host[100] = {0};
    int rc = gethostname(host, 99);
    if (rc) fprintf(stderr, "gethostname failed: %m(%d)", errno);

	sprintf(full_path, "%s/hadoop-%s-udaMOFSupplier-%s.log", rdmalog_dir, getlogin(), host);
	printf("log will go to: %s\n", full_path);
	log_file = fopen (full_path,"a");


    if (!log_file) {
        printf("log will go to stderr\n");
        fprintf(stderr, "log will go to stderr\n");
    	log_file = stderr;
    }
}

//------------------------------------------------------------------------------
void closeLog()
{
    if (log_file && log_file != stderr) {
        log(lsDEBUG, "closing the log...");
    	fclose(log_file);
    	log_file = stderr;  // in case a stubborn thread still write too log
    }
}

//------------------------------------------------------------------------------
void print_backtrace(const char *label)
{
	char **strings;
	void* _backtrace[25];
	int backtrace_size = backtrace(_backtrace, 25);
	strings = backtrace_symbols(_backtrace, backtrace_size);
//	log(lsTRACE, "=== backtrace label=%s: size=%d caller=%s ", label, backtrace_size, strings[1]); // will catch even caller of inline functions too
//*
	log(lsTRACE, "=== label=%s: printing backtrace with size=%d", label, backtrace_size);
	for (int i = 0; i < backtrace_size; i++)
		log(lsTRACE, "=== label=%s: [%i] %s", label, i, strings[i]);
//*/
	free(strings);
}


//------------------------------------------------------------------------------
void log_set_threshold(log_severity_t _threshold)
{
	g_log_threshold = (lsNONE <= _threshold && _threshold <= lsALL) ? _threshold : DEFAULT_LOG_THRESHOLD;
}

//------------------------------------------------------------------------------
void log_func(const char * func, const char * file, int line, log_severity_t severity, const char *fmt, ...)
{
	if (severity <= lsNONE) return; //sanity (no need to check upper bound since we already checked threshold )

    static const char *severity_string[] = {
		"NONE",
		"FATAL",
		"ERROR",
		"WARN",
		"INFO",
		"DEBUG",
		"TRACE",
		"ALL"
    };

    time_t _time = time(0);
    struct tm _tm;
    localtime_r(&_time, &_tm);

    const int SIZE = 1024;
    char s1[SIZE];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(s1, SIZE, fmt, ap);
    va_end(ap);
    s1[SIZE-1] = '\0';

  fprintf(log_file, "%02d:%02d:%02d %-5s [thr=%x %s() %s:%d] %s\n",
		  _tm.tm_hour,
		  _tm.tm_min,
		  _tm.tm_sec,

		  severity_string[severity],

		  (int)pthread_self(), func, file, line,

		  s1);
    fflush(log_file);
}

#if LCOV_AUBURN_DEAD_CODE
/* FileStream class */
NetStream::NetStream(int socket)
{
    this->socket = socket;
}

size_t NetStream::read(void *buf, size_t len)
{
    size_t result = recv(socket, buf, len, 0);
    if (result == (size_t)(-1)) {
        output_stderr("NetStream: recv error, %s",
                      strerror(errno));
    }
    return result;
}


size_t NetStream::write(const void *buf, size_t len)
{
	if (len == 0) {
		log(lsERROR, "write with len=0");
		return 0;
	}

    size_t result = send(socket, buf, len, 0);
    if (result == (size_t)(-1)) {
        output_stderr("NetStream: send error, %s",
                      strerror(errno));
        return 0;
    }
    return result;
}

/******************************************************************
 * The following is for FileStream
 * Imported by Avner from Auburn debug branch
*******************************************************************/
FileStream::FileStream(FILE *file)
{
  this->mFile = file;
}


size_t FileStream::read(void *des, const size_t len,
                        const char *extrasrc, size_t size,
                        int &idx)
{
  fprintf(stderr, "FileStream: read from two srcs not supported\n");
  return -1;
}


bool FileStream::hasMore(size_t nbytes)
{
  fprintf(stderr, "FileStream: hasMore not supported\n");
  return false;
}


size_t FileStream::rewind(size_t nbytes)
{
  fprintf(stderr, "FileStream: rewind not supported\n");
  return -1;
}


size_t FileStream::read(void *buf, size_t len)
{
  size_t result = fread(buf, len, 1, this->mFile);
  if (result == 0) {
    if (feof(mFile)) {
      output_stderr("FileStream: read EOF on file");
     } else {
         output_stderr("FileStream: read ERROR on file");
     }
  }
  return result;
}


size_t FileStream::skip(size_t nbytes)
{
  bool b = 0==fseek(this->mFile, nbytes, SEEK_CUR);
  return b ? nbytes : -1;
}


bool FileStream::close()
{
  return true;
}


size_t FileStream::write(const void *buf, size_t len)
{
  size_t result = fwrite(buf, len, 1, this->mFile);
  if (result != 1) {
    fprintf(stderr,"FileOutStream: write error\n");
    return 0;
  }
  return result;
}

void FileStream::flush()
{
  fflush(this->mFile);
}

FileStream::~FileStream()
{
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
