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


#include <iostream>
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <getopt.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/types.h>
#include <sys/epoll.h>
#include <sys/socket.h>

#include "NetlevComm.h"
#include "C2JNexus.h"
#include "IOUtility.h"
#include "AIOHandler.h"

extern char *rdmalog_dir;
extern uint32_t wqes_perconn;


int parse_options(int argc, char *argv[], netlev_option_t *op) 
{
    char choice;
    struct option longopts[] = {
        {"wqesperconn",   1, NULL, 'w'},
        {"dataport",      1, NULL, 'r'},
        {"merge",         1, NULL, 'a'},
        {"mode",          1, NULL, 'm'},
        {"log",           1, NULL, 'g'},
        {"trace-level",   1, NULL, 't'},
        {"rdmabufsize",   1, NULL, 's'},
        {NULL,            0, NULL,  0 }
    };
    int buf_size;
	errno = 0; // reset before we check!
	while ((choice = getopt_long(argc, argv, "w:r:a:m:g:t:b:s:",

                            longopts, NULL)) != -1) {
        switch (choice) {
        case 'w':
            wqes_perconn = strtol(optarg, NULL, 10);
            if (errno) {
                goto err_options;
            }
            break;
        case 'r':
            op->data_port = strtol(optarg, NULL, 10);
            if (errno) {
                goto err_options;
            }
            break;
        case 'a':
            op->online = strtol(optarg, NULL, 10);
            if (errno) {
                goto err_options;
            }
            break;
        case 'm':
            op->mode = strtol(optarg, NULL, 10);
            /* if (op->mode == STANDALONE) {
                op->base_path = 
                    strdup("MOFServer/MOFS");
            } else {
                op->base_path = NULL;
            } */
            if (errno) {
                goto err_options;
            }
            break;
        case 'g':
            rdmalog_dir=strdup(optarg);
            break;

        case 't':
			{
				log_severity_t  _treshold = (log_severity_t)strtol(optarg, NULL, 10);
				if (errno) {
					goto err_options;
				}
				log_set_threshold(_treshold);
			}
            break;
        case 's':
        	buf_size = strtol(optarg, NULL, 10);
        	buf_size = buf_size *1024;
        	//Aligning the number by AIO_ALIGNMENT
        	if (buf_size > AIO_ALIGNMENT){
        		buf_size = (buf_size>>AIO_ALIGNMENT_EXPO)<<AIO_ALIGNMENT_EXPO;
        	}
        	else{
        		buf_size = AIO_ALIGNMENT;
        	}
			op->buf_size = buf_size;
			if (errno) {
				goto err_options;
			}
            break;
        default: 
        	printf("got invalid command line option choice=%c [%d] \n", choice, choice);
            break;
        }
    }

    return 0;

err_options:

	printf("DEBUG: choice=%c [%d] optarg=%s\n", choice, choice, optarg);

    for (int i=0; i<argc; i++) {
    	printf("DEBUG: argv[%d] = %s\n", i, argv[i]);
    }

    return 1;
}



void free_hadoop_cmd(hadoop_cmd_t &cmd_struct)
{
    for (int i = 0; i < cmd_struct.count - 1; ++i) {
        free(cmd_struct.params[i]);
    } 

    if (cmd_struct.params) {
        free(cmd_struct.params);
    }
}

bool parse_hadoop_cmd(const string &cmd, hadoop_cmd_t &cmd_struct)
{
    /**
     * format of command from hadoop:
     * "no of (header+params):header:param1:param2:..."
     */
    size_t start, end;
    int i;

    start = end = i = 0;
    cmd_struct.params = NULL;

    /* sanity check */
    if (cmd.size() == 0) {
        cmd_struct.count = 1;
        cmd_struct.header= EXIT_MSG;
        return true;
    }

    /* num of argument */
    end = cmd.find(':');
    if(end == cmd.npos) return false;
    int count = atoi(cmd.substr(start, end).c_str());
    cmd_struct.count = count;

    /* header info, the first argument */

    //COVERITY: RM#16001 false alarm. disregard the integer overflow issue
    start = ++end;    
    end = cmd.find(':', start);
    if (end == cmd.npos) {		
        cmd_struct.header = (cmd_item) atoi(cmd.substr(start).c_str());
        return true;
    } else {
        cmd_struct.header = (cmd_item) atoi(cmd.substr(start, end-start).c_str());
    }

    /* the rest of arguments */
    cmd_struct.params = (char **) malloc((count - 1) * sizeof(char *));

    //COVERITY: RM#16001 false alarm. disregard the integer overflow issue
    start = ++end;
    while (i < count - 2) {
        end = cmd.find(':', start);
        if(end == cmd.npos) return false;
        string tmp = cmd.substr(start, end - start);
        cmd_struct.params[i] = strdup(tmp.c_str());

        //COVERITY: RM#16001 false alarm. disregard the integer overflow issue
        start = ++end;
        ++i;
    }
    cmd_struct.params[i] = strdup(cmd.substr(start).c_str());

    return true;
}



void *event_processor(void *context)
{
    int i, nevents, timeout = RDMA_TIMEOUT * 1000;
    struct epoll_event events[32];

    netlev_thread_t *th = (netlev_thread_t *) context;

    /* Epoll will poll/wait for 2 seconds before loops again,
     * So a static variable can trigger the thread to complete in 
     * 2 seconds */
    while (!th->stop) {

        /* Poll events from both main threads and the event channel */
        nevents = epoll_wait(th->pollfd, events, 
                             ARRAY_SIZE(events), timeout);

        if (nevents < 0) {
            if (errno != EINTR) {
            	log(lsERROR, "pollfd=%d: epoll_wait failed for with ret=%d (errno=%d: %m)", th->pollfd, nevents, errno);
                throw new UdaException("failure in epoll_wait");
            }
        } else if (nevents) {
            for (i = 0; i < nevents; i++) {
                progress_event_t *pevent;
                pevent = (progress_event_t *)events[i].data.ptr;
                pevent->handler(pevent, pevent->data);
            }
        } 
    }
	log(lsINFO, "-------->>>>> event_processor thread stopped <<<<<--------");
    return NULL; //quite the compiler
}

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
