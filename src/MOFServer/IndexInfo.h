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

#ifndef INDEX_RECORD_H
#define INDEX_RECORD_H 1

#include <stdint.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <sys/resource.h>

using namespace std;

#include <string>
#include <map>
#include <vector>
#include "LinkList.h"
#include "AIOHandler.h"
#include "../DataNet/RDMAComm.h"


#define AIOHANDLER_MIN_NR			(1)
#define AIOHANDLER_NR				(50)
#define AIOHANDLER_TIMEOUT_IN_NSEC	(300000000)
#define AIOHANDLER_CTX_MAXEVENTS	NETLEV_RDMA_MEM_CHUNKS_NUM

class OutputServer;
class ShuffleReq;
class C2JNexus;
class DataEngine;
struct netlev_conn;

/*
 * structure for counting the current onair aio operations related to a specific fd
 * the counter should be incremented when submitting aio operations and decremented on aio completions
 * the propose is to close the fd when there are no operations onair and reopen the file if necessary
 * incr/decr the counter, close/open an of should be protected by the lock.
 */
typedef struct fd_counter
{
	int				fd;
	int				counter; /* for counting the current number of io operation onair*/
//	pthread_mutex_t	lock;
} fd_counter_t;

/* Format: "jobid:mapid:mop_offset:reduceid:mem_addr:req_prt:chunk_size" */
typedef struct shuffle_req
{
    struct list_head    list;
    struct netlev_conn *conn;

    string    m_jobid;
    string    m_reduceid;
    string    m_map;
    int32_t   reduceID;
    int64_t   map_offset;
    int64_t   remote_addr;
    uint64_t  freq; //saving pointer to client's request
    int32_t	  chunk_size;
} shuffle_req_t;

typedef struct comp_mof_info
{
    struct list_head list;
    char *jobid;
    char *mapid;
} comp_mof_info_t;

typedef struct supplier_state {
    pthread_mutex_t  sm_lock;  /* lock for the global state machine */
    pthread_cond_t   cond; ;   /* conditional signal for thread activation */
    DataEngine      *data_mac; /* data machine    */
    OutputServer    *mover;    /* Transport */
} supplier_state_t;

struct partition_record;


/**
 * partition_record is a 4-tuple <offset, rawLen, partLen, addr> struct
 * that describes the targeted partition by a reducer
 */
typedef struct index_record
{
    int64_t   offset;     /* Offset in the index file */
    int64_t   rawLength;  /* decompressed length of MOF */
    int64_t   partLength; /* compressed size of MOF partition */
    jstring   path; /* path to MOF */
} index_record_t;


/* The wrapper of index record 
   which comes from hadoop design.
   this is for a specific map output file
 */

typedef map<string, fd_counter_t*>::iterator path_fd_iter;

typedef struct partition_table
{
    size_t  total_size;   /* index file size */
    int32_t num_entries;  /* number of actual records */
    string 	idx_path; /* path to index file */
    string 	out_path; /* path to data file */
    index_record_t* records;
} partition_table_t;

typedef struct chunk {
	uint32_t			type; //!!!!!! type must be at offset 0!!!!!! DO NOT MOVE IT!!!!
    struct list_head 	list;
    char*				buff;
} chunk_t;

typedef struct shuffle_request_callback_arg {
	chunk_t*			chunk;
	uint64_t			readLength;
	shuffle_req_t*		shreq;
	supplier_state_t*   state_mac;
	index_record_t*		record;
	int					offsetAligment;
	string	     		fdc_key; // passing key of the fd counter to let the completion event handler to close the fd in case counter=0
	fd_counter_t*		fdc; //passing the value to avoid log(N) for each aio completion
} req_callback_arg;





int aio_completion_handler(void* data, int success);


class DataEngine
{
public:
    supplier_state_t    *state_mac;
    bool                 stop;
    int                  rdma_buf_size;
    JNIEnv               *jniEnv;
    pthread_mutex_t      _data_lock;
    map<string, fd_counter_t*>* _fdc_map;

    DataEngine(void *mem,supplier_state_t *state,
               const char *path, int mode, int rdma_buf_size, struct rlimit kernel_fd_rlim);
    ~DataEngine();

    // produce chunk buffer to pool
    // send condition signal if pool was empty
    void release_chunk(chunk_t* chunk);

    /* XXX:Start the data engine thread for new requests and MOFs */
    void start();


private:
	AIOHandler* 		_aioHandler;
    struct list_head    _free_chunks_list;
    chunk_t*			_chunks;
    pthread_cond_t      _chunk_cond;
    pthread_mutex_t		_chunk_mutex;
    struct rlimit 		_kernel_fd_rlim;



    /*
     * get the specific fd counter structure related with data_path
     * if not exists then create&initialize new one.
     * this method is not THREAD_SAFE
     */
    fd_counter_t* getFdCounter(const string& data_path);


    /**
     * 1) retrieve_path
     * 2) getIFile
     * 3) if necessary then aioHandler->submit() to release chunks
     * 4) occupy_chunk()
     * 5) aio_read_chunk_data
     * return 0 on SUCCESS
     */
    int process_shuffle_request(shuffle_req_t* req);

    /**
     * 1) get opened fd from job to FdCounters map ,  re/open fd with O_DIRECT flag
     * 2) inc fdCounter (aio callback decrements it and closes the fd in case counter=0)
     * 3) prepare suitable callback argument for aio
     * 4) _aioHandler->prepare_read
     */
    int aio_read_chunk_data(shuffle_req_t* req , index_record_t* record, const string &out_path, chunk_t* chunk, uint64_t map_offset);

    // consumes chunk buffer from pool
    // WAIT on condition if no chunks available
    chunk_t* occupy_chunk();

    /* Initialize the cache tables with provided memory */
    void prepare_tables(void *mem, int rdma_buf_size);

    /*
     * 1) cleanJob for all jobs
     * 2) free RDMA chunks
     * 3) destroy all mutex&cond
     *
     * Dtor calls this method
     */
    void cleanup_tables();


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
