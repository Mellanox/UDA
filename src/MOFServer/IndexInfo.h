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

using namespace std;

#include <string>
#include <map>
#include <vector>
#include "LinkList.h"
#include "AIOHandler.h"


#define MAX_RECORDS_PER_MOF     	(2048)
#define AIOHANDLER_MIN_NR			(1)
#define AIOHANDLER_NR				(50)
#define AIOHANDLER_TIMEOUT_IN_NSEC	(300000000)
#define AIOHANDLER_CTX_MAXEVENTS	NETLEV_RDMA_MEM_CHUNKS_NUM

class OutputServer;
class ShuffleReq;
class C2JNexus;
class DataEngine;
struct netlev_conn;

/* Format: "jobID:mapAttempt:offset:reduce:remote_addr"; */
typedef struct shuffle_req
{
    struct list_head    list;
    struct netlev_conn *conn;

    string    m_jobid;
    string    m_reduceid;
    string    m_map;
//    bool      prefetch;
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

typedef struct path_info
{
    int16_t out_pos;
    int16_t idx_pos;
    char  *user_name;
} path_info;


/* The wrapper of index record 
   which comes from hadoop design.
   this is for a specific map output file
 */
typedef struct partition_table
{
    struct list_head list;
    size_t   total_size;   /* index file size */
    int32_t  first_record; /* the first record */
    int32_t  num_entries;  /* number of actual records */
    int32_t  used_times;   /* counts how many time this been used*/ 
    /* XXX: this only favors neighboring reducers to shuffle data */
    index_record_t records[MAX_RECORDS_PER_MOF];
} partition_table_t;

typedef struct chunk {
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
} req_callback_arg;


int aio_completion_handler(void* data);


class DataEngine
{
private:
	AIOHandler* 		_aioHandler;
    struct list_head    _free_chunks_list;
    chunk_t*			_chunks;
    pthread_cond_t      _chunk_cond;
    pthread_mutex_t		_chunk_mutex;

    const uint64_t		MAX_OPEN_DAT_FILES;


public:
    DataEngine(void *mem, size_t total_size,
               size_t chunk_size, supplier_state_t *state,
               const char *path, int mode, int rdma_buf_size, uint64_t max_open_files);
    ~DataEngine();


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
     * 1) get fd from fs_map or open new fd with O_DIRECT flag
     * 2) prepare suitable callback argument for aio
     * 3) calculate buffer, offset and size alignment to SECTOR_SIZE (currently is a constant, probably is 512)
     * TODO: setting SECTOR_SIZE dynamically using system and hd querying
     * 4) _aioHandler->prepare_read
     * 5) handle exceeding number of FDs (currently just exit+error log)
     */
    int aio_read_chunk_data(shuffle_req_t* req , index_record_t *record, chunk_t* chunk,  const string &out_path, uint64_t map_offset);

    // consumes chunk buffer from pool
    // WAIT on condition if no chunks available
    chunk_t* occupy_chunk();

    // produce chunk buffer to pool
    // send condition signal if pool was empty
    void release_chunk(chunk_t* chunk);



	/* return the matching iFile for the specific key(jobid+mapid) from ifiles map
     * If no matching ifile then pull empty ifile from pool
     * if no available ifile on pool then remove oldest from ifiles map , free  current data chunks of pulled ifile and clean it's index records.
     * return NULL if error
     * @param string key a key for a specific ifile is concatanation of jobid + mapid
     * @param bool* is_new if oldest ifile was removed from ifiles map then set is_new as true otherwise set to false
     */
    partition_table_t* getIFile(string key, bool* is_new);

    /* XXX:Start the data engine thread for new requests and MOFs */
    void start();

    /* Initialize the cache tables with provided memory */
    void prepare_tables(void *mem, size_t total_size, size_t chunk_size, int rdma_buf_size);

    void cleanup_tables();

    // read MOF's full index information into the memory
    int read_mof_index_records(const string &jobid, const string &mapid);

    /* read index information into the memory
     * @param partition_table_t ifile memory presentation for the index file.
     * @param const string parent directory for file.out.index.
     * @param int start_index read maximum MAX_RECORDS_PER_MOF 
     *        since this index.
     */
    int read_records(partition_table_t *ifile, const string &idx_path, int start_index);



    /**
     * when a new intermediate map output is 
     * generated, it need notify the dataengine
     * where is it stored.
     * @param const char* out_bdir the dir store file.out
     * @param const char* idx_bdir the dir store file.out.index
     */ 
    void add_new_mof(const char *jobid, 
                     const char *mapid,
                     const char *out_bdir,
                     const char *idx_bdir,
                     const char *user_name);

    /**
     * get the location of file.out and
     * file.out.index.
     * @param string idx_path the URI of the file.out.index
     * @param string out_path the URI of the file.out 
     * @return bool if the pathes are constructed successfully
     */
    bool retrieve_path(const string &jobid,
                       const string &mapid,
                       string &idx_path,
                       string &out_path);

    void clean_job();
    /* XXX:
     * complete data for a shuffle request. 
     * Free and prefetch more data as needed 
     */
    void comp_shuffle_req(shuffle_req_t *sreq);
    partition_table_t* remove_oldest();
    
    supplier_state_t    *state_mac;
    pthread_mutex_t      index_lock;
    pthread_mutex_t      data_lock;
    
    partition_table_t   *ifiles;
    
    struct list_head     free_ifiles;
    struct list_head     comp_mof_list;

    pthread_cond_t       data_cond;
    int                  num_chunks;
    size_t               chunk_size;
    //char                 *base_path; 
    bool                 stop;
    int                  rdma_buf_size;

    /* Map of path to the partition table */
    map<string, partition_table_t*> ifile_map;

    vector<string> spindles;


    /* Map of path to the intermediate map outputs
     * @string is the key: jobid + mapid
     * @path_info holds  the index of directory stored 
     *  in spindles idx_pos & out_pos and username that 
     *  runs the job
     */
    map<string, path_info> mof_path;

    /* Map of opened file.out files */
    map<string, int> fd_map;
};

typedef map<string, partition_table_t*>::iterator idx_map_iter;
typedef map<string, int>::iterator                fd_map_iter;
typedef map<string, path_info>::iterator            path_map_iter; 

#endif

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
