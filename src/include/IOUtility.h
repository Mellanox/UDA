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

#include <string>
#include <cstring>
#include <cstdlib>
#include <cstdio>

extern "C" {
#include <stdint.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
} /* extern "C" */


#ifndef ROCE_IOUTILITY
#ifndef DEBUG_ROCE
#define DEBUG_ROCE 1 
#define ROCE_IOUTILITY 1
#endif

#if (DEBUG_ROCE)
  #define DBG(_x)  ((void)(_x))
#else
  #define DBG(_x)  ((void)0)
#endif

#define NETLEV_MIN(a, b) ((a) > (b)?(b):(a))
#define NETLEV_MAX(a, b) ((a) > (b)?(a):(b))

#define QUOTE(name) #name
#define STR(macro) QUOTE(macro)

#define LCOV_AUBURN_DEAD_CODE 0

/*****************************************
 * An interface for an input stream.
 *****************************************/
class InStream {
public:
    virtual ~InStream(){};
    /**
     * not only read from it own buf, but also from extra src.
     * if it read from the extra src, the idx represents how many
     * data it read from extra src.
     */
    virtual size_t  read(void *des, const size_t len, 
                         const char *extrasrc, size_t size, int &idx) = 0;
    virtual size_t  read   (void *buf, size_t len) = 0;
    virtual size_t  skip   (size_t nbytes) = 0;
    virtual size_t  rewind (size_t nbytes) = 0;
    virtual bool    hasMore(size_t nbytes) = 0;
    virtual bool    close  () = 0;
};


/******************************************
 * An interface for an output stream.
 *****************************************/
class OutStream {
public:
    virtual ~OutStream(){};
    virtual size_t write(const void *buf, size_t len) = 0;
    virtual void flush() = 0;
    virtual bool close() = 0;
};


/*********************************************
 * In Memory input buffer
*********************************************/
class DataStream : public InStream,
                   public OutStream 
{
protected:
    size_t count;
    size_t pos;

public:
    char   *buf;

    DataStream(char*, int32_t);
    DataStream();
    ~DataStream();

    void      reset(char *input, int32_t length);
    void      reset(char *input, int32_t start, int32_t length);
    size_t    skip(size_t);
    size_t    read(void *des, size_t len);
    /*size_t    read(void *des, size_t off, size_t len);*/
    /*not only read from it own buf, but also from extra src.*/
    size_t read(void *des, const size_t len, 
               const char *extrasrc, size_t size, int &idx);
    size_t   rewind(size_t nbytes);
    bool     hasMore(size_t nbytes);
    void     flush();
    bool     close();
    size_t   write (const void *buf, size_t len);
    char*    getData()    {return this->buf;}
    uint32_t  getPosition(){return this->pos;}
    uint32_t  getLength()  {return this->count;}
};

/**********************************************
 * Utility functions for Stream
**********************************************/
class StreamUtility 
{
private:
    StreamUtility(){}
public:
    static void serializeString(const std::string &t, OutStream &stream); 
    static void serializeInt(int32_t t, OutStream &stream);
    static void serializeLong(int64_t t, OutStream &stream);
    static bool deserializeInt(InStream  &stream, int32_t &ret,int *br);
    static bool deserializeLong(InStream &stream, int64_t &ret,int *br);
    static bool deserializeInt (InStream &stream, int32_t &ret, 
                                const char *extrasrc, size_t size, 
                                int &idx, int *br);
    static bool deserializeLong(InStream &stream, int64_t &ret, 
                                const char *extrasrc, size_t size, 
                                int &idx, int *br);
    static bool deserializeString(std::string &t, InStream &stream);
    static int  getVIntSize(int64_t );
    static int 	decodeVIntSize(int byteValue);

};

// -- Avner: Here we start a fully fledged log facility --

enum log_severity_t {
	// NOTE: changes here MUST be reflected in severity_string array in *.cc file
	lsNONE,
	lsFATAL,
	lsERROR,
	lsWARN,
	lsINFO,
	lsDEBUG,
	lsTRACE,
};


/*log functions */
// THE log macro that should be used everywhere...
#define log(severity, ...) if (severity <= g_log_threshold) log_func(__func__, __FILE__, __LINE__, severity, __VA_ARGS__); else


// log backtrace at the desired severity + 'return' value is the backtrace
// TIP: use severity=lsNONE to skip log and only get ret value
std::string print_backtrace(const char *label = NULL, log_severity_t severity = lsTRACE);



class UdaException{
	std::string _fullMessage;
public:
	const char *_info;
	std::string & getFullMessage() {return _fullMessage;}
	UdaException(const char *info);
};

const log_severity_t DEFAULT_LOG_THRESHOLD = lsINFO; // temporary backward compatibility for other developers...
extern log_severity_t g_log_threshold;
void log_set_threshold(log_severity_t _threshold);
void log_set_logging_mode(bool _log_to_uda_file);
void log_func(const char * func, const char * file, int line, log_severity_t severity, const char *fmt, ...); // should not be called directly

void startLogNetMerger();
void startLogMOFSupplier();
void closeLog();


#define output_stderr(...) log(lsERROR, __VA_ARGS__) // support for deprecated code
#define output_stdout(...) log(lsINFO,  __VA_ARGS__) // support for deprecated code
#define write_log(f, dbg, ...) log(lsDEBUG,  __VA_ARGS__) // support for deprecated code


#endif

#if LCOV_AUBURN_DEAD_CODE


/*******************************************
 * A class to read a file as a stream.
 *******************************************/
class NetStream : public InStream,
                  public OutStream
{
public:
    NetStream(int socket);
    virtual ~NetStream() {};
    size_t read(void *, const size_t ,
                const char *, size_t size,
                int &idx)      {return -1;}
    size_t skip(size_t nbytes) {return -1;}
    size_t rewind (size_t)     {return -1;}
    bool   hasMore(size_t)     {return false;}
    bool   close()             {return true;}
    void   flush()             {};
    size_t read(void *, size_t);
    size_t write(const void *, size_t);
private:
    int socket;
};


/*******************************************
 * A class to read a file as a stream.
 * Imported by Avner from Auburn debug branch
 *******************************************/
class FileStream : public InStream,
                   public OutStream
{
public:
  FileStream(FILE *file);
  virtual ~FileStream();
  //InStream
  size_t read(void *des,
              const size_t len,
              const char *extrasrc,
              size_t size,
              int &idx);
  size_t read(void *buf, size_t len);
  size_t rewind (size_t nbytes);
  size_t skip(size_t nbytes);
  bool   hasMore(size_t nbytes);
  bool   close();
  //OutStream
  size_t write(const void *buf, size_t len);
  void   flush();
private:
  FILE *mFile;
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
