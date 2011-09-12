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

#include "atomic.h"

void init_netlev_comp(netlev_comp_t *c)
{
    c->comp  = 0;
    pthread_mutex_init(&c->lock, NULL);
    pthread_cond_init(&c->cond, NULL);
}

void fini_netlev_comp(netlev_comp_t *c)
{
    pthread_mutex_destroy(&c->lock);
    pthread_cond_destroy(&c->cond);
}

void netlev_complete(netlev_comp_t *c)
{
    pthread_mutex_lock(&c->lock);
    c->comp ++;
    pthread_cond_signal(&c->cond);
    pthread_mutex_unlock(&c->lock);
}

void netlev_wait_for_completion(netlev_comp_t *c)
{
    pthread_mutex_lock(&c->lock);
    while (c->comp  == 0)
        pthread_cond_wait(&c->cond, &c->lock);
    c->comp --;
    pthread_mutex_unlock(&c->lock);
}

void init_netlev_atomic(netlev_atomic_t *a)
{
    a->count = 0;
    pthread_mutex_init(&a->lock, NULL);
}

void fini_netlev_aotmic(netlev_atomic_t *a)
{
    pthread_mutex_destroy(&a->lock);
}

int netlev_atomic_read(netlev_atomic_t *a)
{
    int r;
    pthread_mutex_lock(&a->lock);
    r = a->count;
    pthread_mutex_unlock(&a->lock);
    return r;
}

void netlev_atomic_set(netlev_atomic_t *a, int b)
{
    pthread_mutex_lock(&a->lock);
    a->count = b;
    pthread_mutex_unlock(&a->lock);
}

int netlev_atomic_dec_and_test(netlev_atomic_t *a)
{
    int r;
    pthread_mutex_lock(&a->lock);
    r = --a->count;
    pthread_mutex_unlock(&a->lock);
    return (r == 0);
}

void netlev_atomic_inc(netlev_atomic_t *a)
{
    pthread_mutex_lock(&a->lock);
    ++a->count;
    pthread_mutex_unlock(&a->lock);
}

void netlev_atomic_dec(netlev_atomic_t *a)
{
    pthread_mutex_lock(&a->lock);
    --a->count;
    pthread_mutex_unlock(&a->lock);
}

void netlev_atomic_add(int b, netlev_atomic_t *a)
{
    pthread_mutex_lock(&a->lock);
    a->count += b;
    pthread_mutex_unlock(&a->lock);
}

void netlev_atomic_sub(int b, netlev_atomic_t *a)
{
    pthread_mutex_lock(&a->lock);
    a->count -= b;
    pthread_mutex_unlock(&a->lock);
}
/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab
 */

