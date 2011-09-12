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

#ifndef ROCE_FETCHER_MANAGER	
#define ROCE_FETCHER_MANAGER 1

#include <list>
#include "LinkList.h"

struct client_part_req;
struct reduce_task;

class FetchManager
{
public:
    FetchManager(struct reduce_task *task);
    ~FetchManager();

    /* Get the first piece of data */
    int start_fetch_req   (struct client_part_req *req); 

    /* recvd more data, update request status */
    int update_fetch_req  (struct client_part_req *req); 

    struct reduce_task      *task;

    std::list<client_part_req *>  fetch_list;
    pthread_mutex_t          send_lock; 
    pthread_cond_t           send_cond; 
    
    struct list_head         thread_list;  /*XXX: a list of threads */ 
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
