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

#ifndef ROCE_MAPOUTPUT
#define ROCE_MAPOUTPUT	1

#include <set>
#include <map>
#include <list>

#include "MergeQueue.h"
#include "C2JNexus.h"
class Segment;

class MapOutput;
class FetchRequest;
class RawKeyValueIterator;

enum MEM_STATUS    {INIT, FETCH_READY, MERGE_READY, BUSY};
enum MERGE_FLAG    {INIT_FLAG, NEW_MOP, FINAL_MERGE}; 



/* XXX: in the future, we should attempt to enable a buddy system */
typedef struct memory_pool {
    pthread_mutex_t      lock;
    struct list_head     free_descs;
    char                *mem;        
    int32_t              size; //size of a single rdma buffer
    int32_t              num;
    int64_t              total_size;
    struct list_head     register_mem_list;
} memory_pool_t;

/*
 * Struct to represent the reduce request for a MOF partition 
 * 1: Fetch request from hadoop or merge: 
 * 2: Fetch send to the MOFSupplier:
 */
typedef struct client_part_req
{
    int              st;
    int              ed;
    int              total;
    /**
     * Form a new fetch request object.  the default offset for maps is 0.
     * This constructor is basically for the fetching request from hadoop
     */
    struct list_head list;
    int64_t          last_fetched;  /* offset to fetch in a MOF Partition */
    int64_t          total_len;     /* total length of the partition */
    struct host_list *host;
    hadoop_cmd_t     *info; /* [0]:hostname,[1]:jobid,[2]:mapid,[3]:reduceid*/
    MapOutput        *mop;         /* A pointer to mop */
    char             recvd_msg[64];
} client_part_req_t;


typedef struct host_list {
    int               index;
    char             *hostid; 
    pthread_mutex_t   lock;
    struct list_head  list;
    struct list_head  todo_fetch_list;  /* those that need data */
} host_list_t;


/* MapOutput holds the data from one partition */
class MapOutput 
{
public:
     MapOutput(struct reduce_task *task); 
    ~MapOutput();

    pthread_mutex_t         lock; 
    pthread_cond_t          cond;
    mem_desc_t             *mop_bufs[2];
    struct reduce_task     *task;   
    /* fetch request to get data */
    struct client_part_req *part_req;   
    /* indicate which mem_desc should be filled by fetcher*/
    volatile int            staging_mem_idx;  
    /* merging thread use it to indicate 
       if a mop is already in merge queue.*/                          
    int                     mop_id; 
    int64_t                 total_fetched;
    int64_t                 total_len; 

    /* used for testing */
    volatile int            fetch_count;
};


class MergeManager 
{
public:
    MergeManager(int threads, 
                 list_head_t *dir_list, 
                 int online, 
                 struct reduce_task *task,
                 int _num_lpqs);

    ~MergeManager();
  
    pthread_mutex_t      lock; 
    pthread_cond_t       cond;
    volatile MERGE_FLAG  flag;
 
    list_head_t        *dir_list; /*  All end with '/' ? "YES" */
    struct reduce_task *task;
    int                 online;

    /* 
     * The MergeManager hosts these two data structures
     * -- a tree set of segments (ordered by size)
     * -- a priority queue of segments (ordered by first key)
     */
    MergeQueue<Segment*> *merge_queue;
    set<int>             mops_in_queue;
    list<MapOutput *>    fetched_mops;

    int total_count;
	int progress_count;
public:
    const int            num_lpqs;
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
