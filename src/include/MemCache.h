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
