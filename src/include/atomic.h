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

