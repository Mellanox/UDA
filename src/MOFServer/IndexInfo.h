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
	pthread_mutex_t	lock;
} fd_counter_t;

/* Format: "jobID:mapAttempt:offset:reduce:remote_addr"; */
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
    uint64_t   offset;     /* Offset in the index file */
    uint64_t   rawLength;  /* decompressed length of MOF */
    uint64_t   partLength; /* compressed size of MOF partition */
} index_record_t;


/* The wrapper of index record 
   which comes from hadoop design.
   this is for a specific map output file
 */
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
	OutputServer*		mover;
	index_record_t*		record;
	int					offsetAligment;
	fd_counter_t*		fdc; // passing the fd counter to let the completion event handler to close the fd in case counter=0
} req_callback_arg;

int aio_completion_handler(void* data);


class DataEngine
{
public:
    supplier_state_t    *state_mac;
    struct list_head     comp_mof_list;
    int                  num_chunks;
    size_t               chunk_size;
    bool                 stop;
    int                  rdma_buf_size;

    DataEngine(void *mem, size_t total_size,
               size_t chunk_size, supplier_state_t *state,
               const char *path, int mode, int rdma_buf_size, struct rlimit kernel_fd_rlim);
    ~DataEngine();

    /*
     * clean all in-mem index files: partition_tables&index_records
     * clean all fd_counters and close data FDs
     */
    void clean_job(const string& jobid);

    /**
     * when a new intermediate map output is
     * generated, it need notify the dataengine
     * where is it stored.
     * @param const char* out_bdir the dir store file.out
     * @param const char* idx_bdir the dir store file.out.index
     */
    void add_new_mof(comp_mof_info_t* comp,
                     const char *out_bdir,
                     const char *idx_bdir,
                     const char *user_name);

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
    pthread_mutex_t      _data_lock;
    pthread_mutex_t      _index_lock;
    struct rlimit 		_kernel_fd_rlim;
    map<string, map<string, fd_counter_t*>* > _job_fdc_map; // map<jobid, map<data_path, fd_counter>>
    map<string, map<string, partition_table_t*>*> ifile_map; // map< jobid , map< mapid , iFile > >

    /* return the matching iFile for the specific jobid and mapid
	 * or NULL if no much.
	 * this method is not THREAD_SAFE
     */
    partition_table_t* getIFile(const string& jobid, const string& mapid);

    /*
     * add new ifile to the map of job to ifiles
     * true on success or false if and ifile is allready exists for the specific mapid&jobid
     * this method is not THREAD_SAFE
     */
    bool addIFile(const string &jobid, const string &mapid, partition_table_t* ifile);

    /*
     * by a given jobid the method returns the map of mapid to ifile
     * this method is not THREAD_SAFE
     */
    map<string, partition_table_t*>* getJobIfiles(const string& jobid) ;

    /*
     * get the specific fd counter structure related with data_path&jobid
     * if not exists then create&initialize new one.
     * this method is not THREAD_SAFE
     */
    fd_counter_t* getFdCounter(const string& jobid, const string& data_path);

    /*
     * get the map of data_path to fd counter related with the specific jobid
     * return NULL if no fd counters for jobid at all
     * this method is not THREAD_SAFE
     */
    map<string, fd_counter_t*>* getJobFDCounters(const string& jobid);


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
    int aio_read_chunk_data(shuffle_req_t* req , partition_table_t* ifile, chunk_t* chunk,  const string &out_path, uint64_t map_offset);

    // consumes chunk buffer from pool
    // WAIT on condition if no chunks available
    chunk_t* occupy_chunk();

    /* Initialize the cache tables with provided memory */
    void prepare_tables(void *mem, size_t total_size, size_t chunk_size, int rdma_buf_size);

    /*
     * 1) cleanJob for all jobs
     * 2) free RDMA chunks
     * 3) destroy all mutex&cond
     *
     * Dtor calls this method
     */
    void cleanup_tables();

    // read MOF's full index information into the memory
    int read_mof_index_records(const string &jobid, const string &mapid);

    /* reads index information into the memory , uses ifile's idx_path to open the index file
     * @param partition_table_t* ifile - new ifile with uninitialized fields except to idx_path which must be provided correctly
     * @return true for success or false in case of any error within opening&reading the file.
     */
    bool read_records(partition_table_t* ifile);

};

typedef map<string, map<string, fd_counter_t*>* >::iterator job_fdc_map_iter;
typedef map<string, map<string, partition_table_t*>*>::iterator idx_job_map_iter;
typedef map<string, partition_table_t*>::iterator idx_map_iter;
typedef map<string, fd_counter_t*>::iterator path_fd_iter;

#endif

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
