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

extern const char *default_log;
extern char *rdmalog_dir;
extern bool record;
extern uint32_t max_hosts;
extern uint32_t wqes_perconn;

static void usage(const char *cmd)
{
    printf("\nUsage: %s [<options> ... ]\n\n", cmd);
    printf("<options> are the following:\n");
    printf("  -c | --commandport <port> "
                   "  Port to receive commands from Hadoop \n");
    printf("  -r | --dataport    <port> "
                   "  port to do rdma connection \n");
    printf("  -l | --service     <port> "
                   "  Port to listen to launch of new reduce tasks\n");
    printf("  -a | --online      <online>"
                   " If it is online merge\n");
    printf("  -m | --mode        <mode>"
                   "   Stand alone mode or integrated mode\n");
    printf("  -g | --log               "
                   "   Log directory for NetMerger and MOFSupplier\n");
    printf("  -t | --trace-level       "
                   "   threshold for log level for NetMerger and MOFSupplier\n");
    printf("  -v | --version           "
                       "    Display the version of the file and exit\n");
    printf("  -h | --help              "
                   "    Display this help and exit\n\n");
   
    exit(1);
}

int parse_options(int argc, char *argv[], netlev_option_t *op) 
{
    char choice;
    struct option longopts[] = {
        {"maxhosts",	  1, NULL, 'o'},
        {"wqesperconn",   1, NULL, 'w'},
        {"commandport",   1, NULL, 'c'},
        {"dataport",      1, NULL, 'r'},
        {"service",       1, NULL, 'l'},
        {"merge",         1, NULL, 'a'},
        {"mode",          1, NULL, 'm'},
        {"log",           1, NULL, 'g'},
        {"trace-level",   1, NULL, 't'},
        {"rdmabuffers",   1, NULL, 'b'},
        {"rdmabufsize",   1, NULL, 's'},
        {"version",       0, NULL, 'v'},
        {"help",          0, NULL, 'h'},
        {NULL,            0, NULL,  0 }
    };
    int buf_size;
	errno = 0; // reset before we check!
	while ((choice = getopt_long(argc, argv, "o:w:c:r:l:a:m:g:t:b:s:v:h",

                            longopts, NULL)) != -1) {
        switch (choice) {
        case 'o':
            max_hosts = strtol(optarg, NULL, 10);
            if (errno) {
                goto err_options;
            }
            break;
        case 'w':
            wqes_perconn = strtol(optarg, NULL, 10);
            if (errno) {
                goto err_options;
            }
            break;
        case 'c':
            op->cmd_port = strtol(optarg, NULL, 10);
            if (errno) {
                goto err_options;
            }
            break;
        case 'l':
            op->svc_port = strtol(optarg, NULL, 10);
            if (errno) {
                goto err_options;
            }
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
            if (strcmp(rdmalog_dir,
                       default_log) == 0) {
                record = false;
            }
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
        case 'b':
			op->buffers = strtol(optarg, NULL, 10);
			if (errno) {
				goto err_options;
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
        case 'v':
        	printf("Version is %s\n",STR(VERSION_UDA));
        	printf("Compiled on %s, %s\n", __DATE__, __TIME__);
        	exit (1);
        case 'h':
            usage(argv[0]);
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

    usage(argv[0]);
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

void parse_hadoop_cmd(const string &cmd, hadoop_cmd_t &cmd_struct)
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
        return; 
    }

    /* num of argument */
    end = cmd.find(':');
    int count = atoi(cmd.substr(start, end).c_str());
    cmd_struct.count = count;

    /* header info, the first argument */
    start = ++end;    
    end = cmd.find(':', start);
    if (end == cmd.npos) {
        cmd_struct.header = (cmd_item) atoi(cmd.substr(start).c_str());
        return;
    } else {
        cmd_struct.header = (cmd_item) atoi(cmd.substr(start, end-start).c_str());
    }

    /* the rest of arguments */
    char **params = (char **) malloc((count - 1) * sizeof(char *));

    start = ++end;
    while (i < count - 2) {
        end = cmd.find(':', start);
        string tmp = cmd.substr(start, end - start);
        params[i] = strdup(tmp.c_str());
        start = ++end;
        ++i;
    }
    params[i] = strdup(cmd.substr(start).c_str());
    cmd_struct.params = params; 
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
                pthread_exit(NULL);  // TODO: consider exit
            }
        } else if (nevents) {
            for (i = 0; i < nevents; i++) {
                progress_event_t *pevent;
                pevent = (progress_event_t *)events[i].data.ptr;
                //avner - TODO: remove this log line it is extra verbose....
                //log(lsTRACE, "EVENT calling handler=0x%x with data=0x%x; result of: th->pollfd=%d; nevents=%d", pevent->handler, pevent->data, th->pollfd, nevents);
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
