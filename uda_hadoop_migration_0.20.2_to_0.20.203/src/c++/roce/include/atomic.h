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

#ifndef NETLEV_COMP_ATOMIC_H
#define NETLEV_COMP_ATOMIC_H 1

#include <pthread.h>

typedef struct netlev_comp {
    volatile int    comp;  
    pthread_mutex_t lock;
    pthread_cond_t  cond;
} netlev_comp_t;

void init_netlev_comp(struct netlev_comp *c);
void fini_netlev_comp(struct netlev_comp *c);

void netlev_complete(struct netlev_comp *c);
void netlev_wait_for_completion(struct netlev_comp *c);

typedef struct netlev_atomic { 
    volatile int    count; 
    pthread_mutex_t lock;
} netlev_atomic_t;

int  netlev_atomic_read(netlev_atomic_t *a);
void netlev_atomic_set(netlev_atomic_t *a, int b);
int  netlev_atomic_dec_and_test(netlev_atomic_t *a);
void netlev_atomic_inc(netlev_atomic_t *a);
void netlev_atomic_dec(netlev_atomic_t *a);
void netlev_atomic_add(int b, netlev_atomic_t *a);
void netlev_atomic_sub(int b, netlev_atomic_t *a);

#endif

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */

