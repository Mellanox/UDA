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

#include <errno.h>
#include <stdlib.h>
#include <set>
#include <string>
#include <sys/socket.h>

#include "C2JNexus.h"
#include "Merger/InputClient.h"
#include "Merger/reducer.h"
#include "include/IOUtility.h"

using namespace std;


int netlev_dbg_flag = 0;
uint32_t wqes_perconn = 256;

JNIEnv *jniEnv;


/* merger state machine */
merging_state_t merging_sm;



int MergeManager_main(int argc, char* argv[])
{
    log (lsDEBUG, "TEST early print should go to 'real' stderr");

	int  ret;
    struct netlev_option op;
    ret = parse_options(argc, argv, &op);

    startLogNetMerger();

	log(lsINFO, "======== pid=%d ========", getpid() );

    log (lsINFO, "UDA version is %s",STR(VERSION_UDA));
    log (lsINFO, "Compiled on the %s, %s\n", __DATE__, __TIME__);

    log (lsDEBUG, "size of rdma buffer as passed from java is %d\n", op.buf_size);

    /* initalize merging_sm */
    memset(&merging_sm, 0, sizeof(merging_state_t));
//    merging_sm.stop = 0;
    merging_sm.online = op.online;

//    pthread_mutex_init(&merging_sm.lock, NULL);
//    pthread_cond_init(&merging_sm.cond, NULL);

    /* Create a Fetcher
     * -- an event-driven thread responsible for
     * -- create a network connections with the server
     * -- round-robin to process segment requests from all reducers
     */
    merging_sm.client = new InputClient(op.data_port, op.mode, &merging_sm);
    merging_sm.client->start_client();
	log(lsINFO, " AFTER RDMA CLIENT CREATION");

	spawn_reduce_task();

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
