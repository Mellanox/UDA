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


const char * mof_downcall_handler(const std::string & msg)
{

    /* 1. Extract the command from Java */
    hadoop_cmd_t hadoop_cmd;

    /* if hadoop command could not be parsed correctly */
	if(!(parse_hadoop_cmd(msg, hadoop_cmd)))
	{
		log(lsWARN, "Hadoop's command  - %s could not be parsed", msg.c_str());
		return "C++ could not parse Hadoop command";
	}

    log(lsDEBUG, "===>>> GOT COMMAND FROM JAVA SIDE (total %d params): hadoop_cmd->header=%d ", hadoop_cmd.count - 1, (int)hadoop_cmd.header);


    if (hadoop_cmd.header == INIT_MSG) {
        log(lsINFO, "===>>> we got INIT COMMAND");
        /* base path of the directory containing
           the intermediate map output files
        state_mac.data_mac->base_path = strdup(hadoop_cmd.params[0]);*/

    } else if (hadoop_cmd.header == EXIT_MSG) {

        log(lsINFO, "============>>> we got EXIT COMMAND");

    	/* Stop all threads */

		/* rdma listening thread*/
        state_mac.mover->stop_server();

         /* the DataEngine threads */
         state_mac.data_mac->stop = 1;
         pthread_mutex_lock(&state_mac.mover->in_lock);
         pthread_cond_broadcast(&state_mac.mover->in_cond);
         pthread_mutex_unlock(&state_mac.mover->in_lock);
    }

    free_hadoop_cmd(hadoop_cmd);
    return NULL;
}

int MOFSupplier_main(int argc, char *argv[])
{
    int ret;
    struct rlimit open_files_limit;
    struct netlev_option op;
    memset(&op, 0, sizeof(netlev_option_t));
    ret = parse_options(argc, argv, &op);
    
    startLogMOFSupplier();
    
    /* PLEASE DON'T CHANGE THE FOLLOWING LINE - THE AUTOMATION PARSE IT */
    log (lsINFO, "The version is %s",STR(VERSION_UDA));
    log (lsINFO, "Compiled on the %s, %s\n", __DATE__, __TIME__);

    if (getrlimit(RLIMIT_NOFILE, &open_files_limit)) {
    	log(lsWARN, "failed to get rlimit for max open files. errno=%d %m", errno);
    	open_files_limit.rlim_max=0;
    	open_files_limit.rlim_cur=0;
    }
    else {
		/*
		 * The soft limit is the value that the kernel enforces for the corresponding resource.
		 * The hard limit acts as a ceiling for the soft limit
		 */
		log(lsINFO, "Hard limit for open files is %d", open_files_limit.rlim_max);
		log(lsINFO, "Soft limit for open files is %d", open_files_limit.rlim_cur);
	}

    memset(&state_mac, 0, sizeof(supplier_state_t));

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
                                        &state_mac, /* op.base_path */ NULL, op.mode, op.buf_size, open_files_limit);

    return 0;
}

extern "C" void * MOFSupplierRun(void *) {

JNIEnv *jniEnv = UdaBridge_attachNativeThread();
try{

    log (lsDEBUG, "state_mac.data_mac->rdma_buf_size is %d", state_mac.data_mac->rdma_buf_size);
    state_mac.data_mac->start();

    // cleanup code starts here (after thread termination)
    delete state_mac.mover;
    delete state_mac.data_mac;

    log (lsINFO, "==================  C++ 'main' thread exited ======================");
    closeLog();

}
catch(UdaException *ex) {
	log(lsERROR, "got UdaException!");
	UdaBridge_exceptionInNativeThread(jniEnv, ex);
}
catch(...) {
	log(lsERROR, "got general Exception!");
	UdaBridge_exceptionInNativeThread(jniEnv, NULL);
}

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
