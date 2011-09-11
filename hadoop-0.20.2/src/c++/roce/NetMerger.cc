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

#include <stdlib.h>
#include <errno.h>
#include <set>
#include <string>
#include <sys/socket.h>

#include "C2JNexus.h"
#include "Merger/InputClient.h"
#include "Merger/reducer.h"
#include "include/IOUtility.h"

using namespace std;

int netlev_dbg_flag = 0;

/* accept new hadoop reduce task */
static void 
reduce_connection_handler(progress_event_t *pevent, void *ctx)
{
    int nred;
    socklen_t addrlen;
    struct sockaddr_in pin; 
    merging_state_t *state = (merging_state_t *)ctx;

    pthread_mutex_lock(&state->lock);

    do {   
        addrlen = sizeof(pin);
        nred = accept(pevent->fd, (struct sockaddr *)&pin, &addrlen);
    } while (nred < 0 && errno == EINTR);

    if (nred < 0) {   
        if (errno != ECONNABORTED &&
            errno != EAGAIN && errno != EWOULDBLOCK) {   
            output_stderr("Error accepting new connection");
        }
    } 

    reduce_socket_t *sock = 
        (reduce_socket_t *) malloc(sizeof(reduce_socket_t));
    sock->sock_fd = nred;
    INIT_LIST_HEAD(&sock->list);
    list_add_tail(&sock->list, &state->socket_list);
    pthread_cond_broadcast(&state->cond);
    pthread_mutex_unlock(&state->lock);
}

/* merger state machine */
merging_state_t merging_sm;  

/* client handler for commands from tasktracker */
static void 
client_downcall_handler(progress_event_t *pevent, void *ctx)
{
    C2JNexus *nexus = (C2JNexus *)ctx;
    hadoop_cmd_t hadoop_cmd;

    int32_t num_dirs = 0;
    string msg = nexus->recv_string();
    parse_hadoop_cmd(msg, hadoop_cmd); 

    if (hadoop_cmd.header == INIT_MSG) { // This command is not arrived at the moment
        /* at this point, netlev reduce task does not 
         receive this message */ 
        num_dirs = hadoop_cmd.count;
        for (int i = 0; i < num_dirs; ++i) {
            reduce_directory_t *dir;
            dir = (reduce_directory_t *)
                malloc(sizeof(reduce_directory_t));
            dir->path = strdup(hadoop_cmd.params[i]); // AVNER: i replaced [0] -> [i]
            output_stdout(" NetMerger got directory: %s", hadoop_cmd.params[i]);
            list_add_tail(&dir->list, &merging_sm.dir_list);
        }

    } else if (hadoop_cmd.header == EXIT_MSG) {
        nexus->engine.stop = 1;
        merging_sm.stop    = 1;
        pthread_mutex_lock(&merging_sm.lock);
        pthread_cond_broadcast(&merging_sm.cond);
        pthread_mutex_unlock(&merging_sm.lock);
    }
     
    free_hadoop_cmd(hadoop_cmd);
}

int main(int argc, char* argv[])
{
    int  ret;
    struct netlev_option op; 
    ret = parse_options(argc, argv, &op);

    redirect_stderr("NetMerger");
    redirect_stdout("NetMerger");
	
    /* initalize merging_sm */
    memset(&merging_sm, 0, sizeof(merging_state_t));
    merging_sm.stop = 0;
    merging_sm.online = op.online;
    
    /* init map output memory pool */
    memset(&merging_sm.mop_pool, 0, sizeof(memory_pool_t));
    create_mem_pool(NETLEV_RDMA_MEM_CHUNK_EXPO, 
                    NETLEV_MAX_MOFS_INCACHE, 
                    &merging_sm.mop_pool);

    pthread_mutex_init(&merging_sm.lock, NULL);
    pthread_cond_init(&merging_sm.cond, NULL);

    INIT_LIST_HEAD(&merging_sm.dir_list);
    INIT_LIST_HEAD(&merging_sm.socket_list);
    INIT_LIST_HEAD(&merging_sm.task_list);

    /* Create a nexus talking back to the TaskTracker,
     * -- An event-driven thread responsible for
     * -- connect back to the TaskTracker
     * -- receiving reducer connection requests
     *    o insert a request for new reduceTask to state-machine
     *    o generate a new epoll set for the reduceTask
     *    o create a socket to receive fetch requests from the reducer
     *    o use the socket to report progress for the reducer 
     *    o insert the new socket to the same epoll event set
     *    o create a reducer for merging the segments for the reducer
     * -- inserting new segment requests to different reducer
     */
    merging_sm.nexus = new C2JNexus(op.mode, op.cmd_port, 
                                    client_downcall_handler,
                                    op.svc_port, 
                                    reduce_connection_handler, 
                                    &merging_sm);

    /* Create a Fetcher
     * -- an event-driven thread responsible for
     * -- create a network connections with the server
     * -- round-robin to process segment requests from all reducers
     */
    merging_sm.client = new InputClient(op.data_port, op.mode, &merging_sm);
    merging_sm.client->start_client();
    merging_sm.client->rdma->register_mem(&merging_sm.mop_pool);

    /* XXX: 
     * -- main thread listens for newly established sockets
     * -- check if Nexus has requested to exit
     */
    while (!merging_sm.stop) {
        reduce_socket_t *sock = NULL; 

        if (INTEGRATED == op.mode) {
            
            if (!list_empty(&merging_sm.socket_list)) {
                pthread_mutex_lock(&merging_sm.lock);
                sock = list_entry(merging_sm.socket_list.next,
                                  typeof(*sock), list);
                list_del(&sock->list);
                pthread_mutex_unlock(&merging_sm.lock);
            }

            if (sock) {
                struct reduce_task *task = NULL;
                task = spawn_reduce_task(op.mode, sock);

                pthread_mutex_lock(&merging_sm.lock);
                list_add_tail(&task->list, &merging_sm.task_list);
                pthread_mutex_unlock(&merging_sm.lock);
                free(sock);
            }


            pthread_mutex_lock(&merging_sm.lock);
            if (!list_empty(&merging_sm.socket_list)) {
                pthread_mutex_unlock(&merging_sm.lock);
                continue;
            }
            pthread_cond_wait(&merging_sm.cond, &merging_sm.lock);
            pthread_mutex_unlock(&merging_sm.lock);
        
        } else { 
            
            /* for stand alone mode test */
            reduce_task_t *task = NULL;
            task = spawn_reduce_task(op.mode, NULL);
            list_add_tail(&task->list, &merging_sm.task_list);
            while (!merging_sm.stop) {
                pthread_mutex_lock(&merging_sm.lock);
                pthread_cond_wait(&merging_sm.cond, &merging_sm.lock);
                pthread_mutex_unlock(&merging_sm.lock);
            }
        }
    }
    output_stdout("main thread exit");

    /* release all working netlev reduce tasks,
       under normal situation, this list at this
       point shall be empty */
    /*FIXME: list_del(task) in reducer.cc cause
             segment fault.
    while (!list_empty(&merging_sm.task_list)) {
        reduce_task_t *task = NULL;
        task = list_entry(merging_sm.task_list.next, typeof(*task), list);
        finalize_reduce_task(task);
    }
    DBGPRINT(DBG_CLIENT, "all reduce tasks are cleaned\n");
    */

   
    /* free map output pool */
    while (!list_empty(&merging_sm.mop_pool.free_descs)) {
        mem_desc_t *desc = 
            list_entry(merging_sm.mop_pool.free_descs.next, 
                       typeof(*desc), list);
        list_del(&desc->list);
        free(desc);
    }
    pthread_mutex_destroy(&merging_sm.mop_pool.lock);
    free(merging_sm.mop_pool.mem);
    output_stdout("mop pool is freed");
 
    merging_sm.client->stop_client();
    output_stdout("client is stoped");
    
    delete merging_sm.client;
    output_stdout("client is deleted");
    
    delete merging_sm.nexus;
    output_stdout("nexus is deleted");

    pthread_mutex_destroy(&merging_sm.lock);
    pthread_cond_destroy(&merging_sm.cond);
    fclose(stdout);
    fclose(stderr);
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
