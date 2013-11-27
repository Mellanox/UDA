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

#ifndef ROCE_MAPOUTPUT
#define ROCE_MAPOUTPUT	1

#include <set>
#include <map>
#include <list>

#include "MergeQueue.h"
#include "C2JNexus.h"
class BaseSegment;
class AioSegment;

class MapOutput;
class KVOutput;
class FetchRequest;
class RawKeyValueIterator;

enum MEM_STATUS    {INIT, FETCH_READY, MERGE_READY, BUSY};
enum MERGE_FLAG    {INIT_FLAG, NEW_MOP, FINAL_MERGE}; 

#define MERGE_AIOHANDLER_MIN_NR			(1)
#define MERGE_AIOHANDLER_NR				(50)
#define MERGE_AIOHANDLER_TIMEOUT_IN_NSEC	(300000000)
#define MERGE_AIOHANDLER_CTX_MAXEVENTS         (100)

// callback for aio completions of LPQ output write submits
int aio_lpq_write_handler(void* data);

// callback for aio completions of RPQ input read submits
int aio_rpq_read_handler(void* data);

// argument for aio submitions to be used by completion callback of LPQs phase (spill output)
typedef struct lpq_aio_arg
{
	mem_desc*			desc; // for setting the status to FETCH_READY and broadcast
	int					fd; // to close in case of last write for LPQ
	bool				last_lpq_submition; // indicates that this completion is the last write for LPQ
	const char*			filename; // filename to reopen withou O_DIRECT and write blocking the last unaligned amount of data
	int					aligment_carry_size; // last unaligned data size
	char*				aligment_carry_buff; // last unaligned data
	uint64_t			aligment_carry_fileOffset; // offset if filename to write the last unaligned data
} lpq_aio_arg_t ;

// argument for aio submitions to be used by completion callback of RPQs phase (read spilled LPQs)
typedef struct rpq_aio_arg
{
	mem_desc*			desc; // for setting the status to MERGE_READY
	uint64_t			size; // for updateing the segment
	KVOutput*			kv_output; // for updateing and broadcast
	BaseSegment*		segment; // for sending request for first completions
} rpq_aio_arg_t ;


/* XXX: in the future, we should attempt to enable a buddy system */
typedef struct memory_pool {
    pthread_mutex_t      lock;
//    pthread_cond_t       cond; //this cond should be used in case the reducer is running several LPQs simultaneously
    struct list_head     free_descs;
    char                *mem;        
    int32_t              num;
    int64_t              total_size;
    mem_desc_t			*desc_arr;
    mem_set_desc_t		*pair_desc_arr;
    struct list_head     register_mem_list;
} memory_pool_t;

/*
 * Struct to represent the reduce request for a MOF partition 
 * 1: Fetch request from hadoop or merge: 
 * 2: Fetch send to the MOFSupplier:
 */
typedef struct client_part_req
{
    /**
     * Form a new fetch request object.  the default offset for maps is 0.
     * This constructor is basically for the fetching request from hadoop
     */
    struct list_head list;
    struct host_list *host;
    hadoop_cmd_t     *info; /* [0]:hostname,[1]:jobid,[2]:mapid,[3]:reduceid*/
    MapOutput        *mop;         /* A pointer to mop */
    char             recvd_msg[64];

    bool 				request_in_queue;
} client_part_req_t;


typedef struct host_list {
    int               index;
    char             *hostid; 
    pthread_mutex_t   lock;
    struct list_head  list;
//    struct list_head  todo_fetch_list;  /* those that need data */
} host_list_t;

class KVOutput  {
public:
    pthread_mutex_t         lock; 
    pthread_cond_t          cond;
    mem_desc_t             *mop_bufs[NUM_STAGE_MEM];
    struct reduce_task     *task;
    
    /* indicate which mem_desc should be filled by fetcher*/
    volatile int            staging_mem_idx;  
    
    int64_t          		last_fetched;  /*represents how many bytes were fetched in the last time */
//    int64_t                 total_fetched;

    int64_t                 fetched_len_rdma; //represents #bytes fetched (current offset)
    int64_t                 fetched_len_uncompress; //represents total #bytes ready to read

//    int64_t                 total_len;
    int64_t                 total_len_rdma; //represents raw size of MOF partition (either with compression, or uncompressed size without compression)
    int64_t                 total_len_uncompress; //represents decompressed length of MOF
    
    KVOutput(struct reduce_task *task);
	virtual ~KVOutput();
	int32_t getFreeBytes();
};

/* MapOutput holds the data from one partition */
class MapOutput : public KVOutput 
{
public:
     MapOutput(struct reduce_task *task);
     MapOutput(); 
    ~MapOutput();

    /* fetch request to get data */
    struct client_part_req *part_req;   
    
    int                     mop_id; 

    /* used for testing */
    volatile uint64_t  fetch_count;
};



class MergeManager 
{
public:
    MergeManager(int threads, 
                 int online, 
                 struct reduce_task *task,
                 int _num_lpqs);

    ~MergeManager();
  
    void start_fetch_req(client_part_req_t *req);
    int update_fetch_req(client_part_req_t *req);
    void mark_req_as_ready(client_part_req_t *req);
    void allocate_rdma_buffers(client_part_req_t *req);

    pthread_mutex_t      lock; 
    pthread_cond_t       cond;
    volatile MERGE_FLAG  flag;
    std::list<client_part_req *>  fetch_list;
 
//    list_head_t        *dir_list; /*  All end with '/' ? "YES" */
    struct reduce_task *task;
    int                 online;


    /* 
     * The MergeManager hosts these two data structures
     * -- a tree set of segments (ordered by size)
     * -- a priority queue of segments (ordered by first key)
     */
    MergeQueue<BaseSegment*> *merge_queue;
    set<int>             mops_in_queue;
    list<MapOutput *>    fetched_mops;

    int                  total_count;
    int                  progress_count;
public:
    const int            num_lpqs;
    const int            num_mofs_in_lpq;
    const int            num_regular_lpqs;

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
