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
#include "MOFServer/MOFServlet.h"
#include "MOFServer/IndexInfo.h"
#include "include/IOUtility.h"

using namespace std;

int netlev_dbg_flag = 0;

supplier_state_t state_mac;

void mof_downcall_handler(progress_event_t *pevent, void *ctx)
{
    C2JNexus *nexus = (C2JNexus *)ctx;

    /* 1. Extract the command from Java */
    string msg = nexus->recv_string();
    hadoop_cmd_t hadoop_cmd;
    parse_hadoop_cmd(msg, hadoop_cmd);

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

        state_mac.data_mac->add_new_mof(comp->jobid,
                                        comp->mapid,
                                        hadoop_cmd.params[2],
                                        hadoop_cmd.params[3]);

        pthread_mutex_lock(&state_mac.data_mac->index_lock);
        list_add_tail(&comp->list, 
                      &state_mac.data_mac->comp_mof_list);
        pthread_mutex_unlock(&state_mac.data_mac->index_lock);

        /* XXX: Wake up DataEngine threads to do prefetchin. 
         * Mutex not required but good to have for better scheduling */
        pthread_cond_broadcast(&state_mac.mover->in_cond);
        /* pthread_mutex_lock(&state_mac.sm_lock);
        pthread_cond_broadcast(&state_mac.cond);
        pthread_mutex_unlock(&state_mac.sm_lock); */

    } else if (hadoop_cmd.header == INIT_MSG) {
        /* base path of the directory containing 
           the intermediate map output files 
        state_mac.data_mac->base_path = strdup(hadoop_cmd.params[0]);*/

    } else if (hadoop_cmd.header == JOB_OVER_MSG) {
        string jobid = hadoop_cmd.params[0];
        state_mac.mover->clean_job();
        state_mac.data_mac->clean_job();

    } else if (hadoop_cmd.header == EXIT_MSG) {
        /* Stop all threads */

         /* hadoop comand thread */
         nexus->engine.stop = 1;

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


int main(int argc, char *argv[])
{
    int ret;
    struct netlev_option op;
    memset(&op, 0, sizeof(netlev_option_t));
    ret = parse_options(argc, argv, &op);
    
    redirect_stderr("MOFSupplier");
    redirect_stdout("MOFSupplier");
    
    memset(&state_mac, 0, sizeof(supplier_state_t));
    pthread_mutex_init(&state_mac.sm_lock, NULL);
    pthread_cond_init(&state_mac.cond, NULL);

    /* Create a nexus talking back to the supplier,
     * -- An event-driven thread responsible for
     * -- receiving control commands; 
     * -- inserting new MOFs into DataEngine
     * XXX: note that the context and the service are NULL 
     */
    state_mac.nexus = new C2JNexus(op.mode, op.cmd_port, 
                                   mof_downcall_handler, 
	                               0, NULL, NULL);

    /* Create an OutputServer
     * -- an event-driven thread responsible for
     * -- create connections with clients
     * -- receive and insert new fetch requests to Data Engine
     */
    state_mac.mover = new OutputServer(op.data_port, op.mode, 
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
                                        &state_mac, /* op.base_path */ NULL, op.mode);
    state_mac.data_mac->start();

    delete state_mac.mover;
    delete state_mac.nexus;
    delete state_mac.data_mac;

    pthread_mutex_destroy(&state_mac.sm_lock);
    pthread_cond_destroy(&state_mac.cond);
  
    fclose(stdout);
    fclose(stderr);

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
