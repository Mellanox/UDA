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

#include <string>
#include <map>
#include <vector>
#include "LinkList.h"

using namespace std;
extern "C" {
#include <stdint.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
}; /* extern "C" */

#define MAX_RECORDS_PER_MOF     (256)
#define MAX_OPEN_DAT_FILES      (512)

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
    void               *peer_wqe;

    string    m_jobid;
    string    m_reduceid;
    string    m_map;
    bool      prefetch;
    int32_t   reduceID;
    int64_t   map_offset;
    int64_t   remote_addr;
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
    C2JNexus        *nexus;    /* control channel */
    DataEngine      *data_mac; /* data machine    */
    OutputServer    *mover;    /* Transport */
} supplier_state_t;

struct partition_record;

typedef struct partition_data {
    struct list_head         list;
    volatile int8_t          status;/* status of this chunk */
    uint64_t                 map_offset;/* offset for this partition */
    struct partition_record  *rec;
    char                     *buff;/*this buf is never released*/
} partition_data_t;

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

typedef struct partition_record
{
    index_record_t    rec;
    partition_data_t *data;       /* a pointer to the data */
} partition_record_t;

/* path_info struct holds data that together with
 *  * array mof_path form the beginning of path to
 *   * index file and out file
 *    */
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
    partition_record_t records[MAX_RECORDS_PER_MOF]; 
} partition_table_t;


class DataEngine
{
public:
    DataEngine(void *mem, size_t total_size,
               size_t chunk_size, supplier_state_t *state,
               const char *path, int mode);
    ~DataEngine();

    /* XXX:Start the data engine thread for new requests and MOFs */
    void start();

    /* Initialize the cache tables with provided memory */
    void prepare_tables(void *mem, size_t total_size, size_t chunk_size);

    void cleanup_tables();
    void unlock_chunk(partition_data_t*);
    void lock_chunk(partition_data_t*);

    /* Prefetch a MOF index file and its MOF data into cache 
     * @param string idx_path the URL of file.out.index.
     * @param string out_path the URL of file.out.
     * @param string key the combination of jobid + mapid.
     */
    partition_table_t *prefetch_mof(const string &idx_path,
                                    const string &out_path, 
                                    const string &key,
                                    int index,
                                    uint64_t map_offset,
                                    bool prefetch_all);

    /* read index information into the memory
     * @param partition_table_t ifile memory presentation for the index file.
     * @param const string parent directory for file.out.index.
     * @param int start_index read maximum MAX_RECORDS_PER_MOF 
     *        since this index.
     */
    int read_records(partition_table_t *ifile, 
                     const string &idx_path,
                     int start_index);

    /* Extract a partition record for a MOF */
    partition_record_t *get_record_by_path(const string &jobid, 
                                           const string &mapid, 
                                           int index, 
                                           uint64_t map_offset);

    partition_data_t *get_new_chunk();

    /* Read in concrete <k,v> data from file.out into the mem chunk 
     * @param partition_table_t ifile memory index infor
     * @param const string the parent path to the file.out file
     * @param int record_index specify for which reducer.
     * @param uint64_t map_offset start position for reading data chunk.
     * @param uint32_t length ideal maximum length to read into memory
     */
    void read_chunk_data(partition_table_t *ifile,
                         const string &out_path, 
                         int record_index, 
                         uint64_t map_offset, 
                         uint32_t length);

    /* push data for a shuffle request */
    int push_shuffle_req(shuffle_req_t *sreq);

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
    
    partition_table_t    *ifiles;
    partition_data_t     *chunks;
    
    struct list_head     free_ifiles;
    struct list_head     free_chunks;
    struct list_head     comp_mof_list;

    pthread_cond_t       data_cond;
    int                  num_chunks;
    size_t               chunk_size;
    //char                 *base_path; 
    bool                 stop;

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
