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

#ifndef ROCE_MEMCACHE
#define ROCE_MEMCACHE 1
#define ptr_from_int64(p) (void *)(unsigned long)(p)
#define int64_from_ptr(p) (u_int64_t)(unsigned long)(p)

typedef struct memcache_entry {
    struct list_head list;
    void *buf;
    int   len;
    int   count;  /* refcount, usage of this entry */

    /* IB-specific fields */
    struct {
        uint64_t mrh;   /* pointer on openib, 32-bit int on vapi */
        uint32_t lkey;  /* 32-bit mandated by IB spec */
        uint32_t rkey;
    } memkeys;
    struct mrr_dev *dev;
} memcache_entry_t;

/*
 * Memory allocation and caching internal functions, in mem.c.
 */ 
void *memcache_memalloc(void *md, int len, int eager_limit);
int memcache_memfree(void *md, void *buf, int len);
void memcache_register(void *md, xio_rdma_veclist_t *veclist);
void memcache_preregister(void *md, const void *buf, int len);
void memcache_deregister(void *md, xio_rdma_veclist_t *veclist);
void *memcache_init();
void memcache_shutdown(void *md);
void memcache_cache_flush(void *md);

#endif

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
