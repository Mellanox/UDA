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

/*********************************************
 * In Memory input buffer
*********************************************/
class DataStream : public InStream,
                   public OutStream 
{
protected:
    char   *buf;
    int32_t count;
    int32_t pos;

public:
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
    int32_t  getPosition(){return this->pos;}
    int32_t  getLength()  {return this->count;}
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
};

/*log functions */ 
void write_log(FILE *log, int dbg, char *fmt, ...);
FILE* create_log(char *log_name); 
void close_log(FILE *log);
void redirect_stderr(char *);
void redirect_stdout(char *);
void output_stderr(char *fmt, ...);
void output_stdout(char *fmt, ...);

#endif

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
