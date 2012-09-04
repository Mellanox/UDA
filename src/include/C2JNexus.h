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

#ifndef ROCE_CPP_SIDE
#define ROCE_CPP_SIDE 1

#include <string>

extern "C" {
#include <stdint.h>
}

#include "NetlevComm.h"

#define STANDALONE 0
#define INTEGRATED 1

using namespace std;

enum cmd_item {
    EXIT_MSG       = 0,
    NEW_MAP_MSG    = 1,
    FINAL_MSG      = 2,
    RESULT         = 3,
    FETCH_MSG      = 4,
    FETCH_OVER_MSG = 5,
    JOB_OVER_MSG   = 6,
    INIT_MSG       = 7,
    MORE_MSG       = 8,
    RT_LAUNCHED = 9
};

class NetStream;


typedef struct hadoop_cmd {
    int            count;
    cmd_item       header;
    char         **params;
} hadoop_cmd_t;


typedef struct netlev_option {
    int data_port;   /* port to do rdma connection */ 
    int mode;        /* standalone or integrated*/
    int online;      /* if we are using online merge*/
    //char *base_path; /* file path contains the intermediate mop*/
    int buf_size;    /* size of rdma buffer*/
} netlev_option_t;


int parse_options(int argc, char *argv[], netlev_option_t *op);
void free_hadoop_cmd(hadoop_cmd_t &);
bool parse_hadoop_cmd(const string &, hadoop_cmd_t &);

#endif

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
