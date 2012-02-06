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

#include <sys/resource.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>

#include "MOFServer/MOFServlet.h"
#include "MOFServer/IndexInfo.h"
#include "include/IOUtility.h"

using namespace std;
/*
 - Avner: commented out to avoid duplication in lib with same var in NetMergerMain.cc
- TODO: the last 2 may be constants
int netlev_dbg_flag = 0;
uint32_t wqes_perconn = 256;
*/
supplier_state_t state_mac;


void mof_downcall_handler(const std::string & msg)
{

    /* 1. Extract the command from Java */
    hadoop_cmd_t hadoop_cmd;
    parse_hadoop_cmd(msg, hadoop_cmd);

    log(lsDEBUG, "===>>> GOT COMMAND FROM JAVA SIDE (total %d params): hadoop_cmd->header=%d ", hadoop_cmd.count - 1, (int)hadoop_cmd.header);

    if (hadoop_cmd.header == NEW_MAP_MSG) {
        /*2. Insert the MOF */
        comp_mof_info_t *comp = NULL;

        /*
         * 1. Create a new MOF entry
         * 2. Insert it to the list of DataEngine
         * hadoop_cmd.params[0]: jobid;
         * hadoop_cmd.params[1]: mapid;
         * hadoop_cmd.params[2]: file.out base directory
         * hadoop_cmd.params[3]: file.idx base directory
         */
        comp = (comp_mof_info_t*) malloc(sizeof(comp_mof_info_t));
        comp->jobid = strdup(hadoop_cmd.params[0]);
        comp->mapid = strdup(hadoop_cmd.params[1]);

        log(lsDEBUG, "NEW_MAP_MSG: jobid=%s, mapid=%s", comp->jobid, comp->mapid);

        if (hadoop_cmd.count>5){
            /*hadoop version >=0.2.203.
             * user name is passed and is part of path to out and index files*/
            state_mac.data_mac->add_new_mof(comp,
                                        hadoop_cmd.params[2],
                                        hadoop_cmd.params[3],
                                        hadoop_cmd.params[4]);
        }
        else{
            /*hadoop version == 0.2.20 user name is not passed.
             * "taskTracker" is part of path to out and index files */

           state_mac.data_mac->add_new_mof(comp,
                                        hadoop_cmd.params[2],
                                        hadoop_cmd.params[3],
                                        "taskTracker");


        }

        /* XXX: Wake up DataEngine threads to do prefetchin.
         * Mutex not required but good to have for better scheduling */
        pthread_cond_broadcast(&state_mac.mover->in_cond);
        /* pthread_mutex_lock(&state_mac.sm_lock);
        pthread_cond_broadcast(&state_mac.cond);
        pthread_mutex_unlock(&state_mac.sm_lock); */

    } else if (hadoop_cmd.header == INIT_MSG) {
        log(lsINFO, "===>>> we got INIT COMMAND");
        /* base path of the directory containing
           the intermediate map output files
        state_mac.data_mac->base_path = strdup(hadoop_cmd.params[0]);*/

    } else if (hadoop_cmd.header == JOB_OVER_MSG) {
        log(lsINFO, "======>>> we got JOB OVER COMMAND");
        string jobid = hadoop_cmd.params[0];
        // TODO : clean job for RDMA client
        state_mac.data_mac->clean_job(jobid);
        log(lsINFO,"JOB OVER ***************************** %s", jobid.c_str());

    } else if (hadoop_cmd.header == EXIT_MSG) {

        log(lsINFO, "============>>> we got EXIT COMMAND");

    	/* Stop all threads */

         /* rdma listening thread*/
         state_mac.mover->rdma->helper.stop = 1;

         /* the DataEngine threads */
         state_mac.data_mac->stop = 1;
         pthread_mutex_lock(&state_mac.sm_lock);
         pthread_cond_broadcast(&state_mac.cond);
         pthread_mutex_unlock(&state_mac.sm_lock);

         pthread_cond_broadcast(&state_mac.mover->in_cond);
    }

    free_hadoop_cmd(hadoop_cmd);
}

int MOFSupplier_main(int argc, char *argv[])
{
    int ret;
    struct rlimit open_files_limit;
    struct netlev_option op;
    memset(&op, 0, sizeof(netlev_option_t));
    ret = parse_options(argc, argv, &op);
    
    startLogMOFSupplier();
  
    log (lsINFO, "The version is %s",STR(VERSION_UDA));
    log (lsINFO, "Compiled on the %s, %s\n", __DATE__, __TIME__);

    if (getrlimit(RLIMIT_NOFILE, &open_files_limit)) {
    	log(lsFATAL, "failed to get max number of open files. errno=%d %m", errno);
    	exit(-1);
    }

    /*
     * The soft limit is the value that the kernel enforces for the corresponding resource.
     * The hard limit acts as a ceiling for the soft limit
     */
    log(lsINFO, "Hard limit for open files is %d", open_files_limit.rlim_max);
    log(lsINFO, "Soft limit for open files is %d", open_files_limit.rlim_cur);
    log(lsINFO, "Limits MOFSupplier for %d open MOFs", open_files_limit.rlim_cur);


    memset(&state_mac, 0, sizeof(supplier_state_t));
    pthread_mutex_init(&state_mac.sm_lock, NULL);
    pthread_cond_init(&state_mac.cond, NULL);

    /* Create an OutputServer
     * -- an event-driven thread responsible for
     * -- create connections with clients
     * -- receive and insert new fetch requests to Data Engine
     */
    state_mac.mover = new OutputServer(op.data_port, op.mode, op.buf_size,
                                       /* op.base_path,*/ &state_mac);
    state_mac.mover->start_server();

    /* Create a data engine, the central player of the supplier 
     * -- contains a list of MOFs
     * -- contains indexcache and dataCache for MOFs
     * -- a list of requests for data fetch
     * -- a list of requests that have posted data
     *
     * Most importantly, it should have a number of threads
     * -- prepare the data cache
     * -- process incoming fetch requests
     * -- transport the data
     * -- grow/shrink the number of threads with the length of requests
     * -- dynamically triggered by signals
     */
    state_mac.data_mac = new DataEngine(state_mac.mover->rdma->rdma_mem,
                                        state_mac.mover->rdma->rdma_total_len,
                                        state_mac.mover->rdma->rdma_chunk_len,
                                        &state_mac, /* op.base_path */ NULL, op.mode, op.buf_size, open_files_limit.rlim_cur);

    return 0;
}

extern "C" void * MOFSupplierRun(void *) {

    log (lsDEBUG, "state_mac.data_mac->rdma_buf_size is %d", state_mac.data_mac->rdma_buf_size);
    state_mac.data_mac->start();

    // cleanup code starts here (after thread termination)
    delete state_mac.mover;
    delete state_mac.data_mac;

    pthread_mutex_destroy(&state_mac.sm_lock);
    pthread_cond_destroy(&state_mac.cond);

    log (lsINFO, "==================  C++ 'main' thread exited ======================");
    closeLog();

    /* if (op.base_path) { 
        free(op.base_path);
    } */

    return 0;
}

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
