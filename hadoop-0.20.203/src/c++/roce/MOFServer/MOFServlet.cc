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

#include <dirent.h>

#include "IOUtility.h"
#include "MOFServlet.h"

using namespace std;

/* Parse param into a shuffle_req_t */
shuffle_req_t* get_shuffle_req(const string &param)
{
    size_t start, end;
    shuffle_req_t *sreq;
    
    start = end = 0;
    sreq = new shuffle_req_t();

    end = param.find(':');
    sreq->m_jobid = param.substr(0, end);

    start = ++end;
    end = param.find(':', start);
    sreq->m_map = param.substr(start, end - start);

    start = ++end;
    end = param.find(':', start);
    sreq->map_offset = atoi(param.substr(start, end - start).c_str());

    start = ++end;
    end = param.find(':', start);
    sreq->reduceID = atoi(param.substr(start, end - start).c_str());

    start = ++end;
    end = param.find(':', start);
    sreq->remote_addr = atoll(param.substr(start, end - start).c_str());

    sreq->prefetch = false;
    return sreq;
}


OutputServer::OutputServer(int data_port, int mode, 
                           supplier_state_t *state)
{
    this->data_port = data_port;
    this->rdma = NULL; 
    this->tcp  = NULL;
    this->state = state;
    INIT_LIST_HEAD(&this->incoming_req_list);

    pthread_mutex_init(&this->in_lock, NULL);
    pthread_mutex_init(&this->out_lock, NULL);
    pthread_cond_init(&this->in_cond, NULL);
    /* if (mode == STANDALONE) {
        list_fet_req(path);
    } */
}

OutputServer::~OutputServer()
{
    pthread_mutex_destroy(&this->in_lock);
    pthread_mutex_destroy(&this->out_lock);
    pthread_cond_destroy(&this->in_cond);
}


void OutputServer::start_server()
{
    this->rdma = new RdmaServer(this->data_port, this->state);
    this->rdma->start_server();
}

void OutputServer::stop_server()
{
    this->rdma->stop_server();
    delete this->rdma;
}

void OutputServer::insert_incoming_req(shuffle_req_t *req)
{
    pthread_mutex_lock(&in_lock);

    /* testing section */
    /* if (req->map_offset == 0) {
        int reduceid = req->reduceID;
        map<int, int>::iterator iter =
            recv_stat.find(reduceid);
        if (iter != recv_stat.end()) {
            recv_stat[reduceid] = (*iter).second + 1;
        } else {
            recv_stat[reduceid] = 1;
        }
        output_stdout("reducer : %d, First mop recv: %d",
                      reduceid, recv_stat[reduceid]);
    } */

    list_add_tail(&req->list, &incoming_req_list);
    pthread_mutex_unlock(&in_lock);
    pthread_cond_broadcast(&in_cond);
}

void OutputServer::start_outgoing_req(shuffle_req_t *req, 
                                      partition_record_t *record)
{
    int send_bytes, len;
    char ack[NETLEV_FETCH_REQSIZE];
    uint64_t req_size;
    uintptr_t local_addr;
    partition_data_t *chunk;

    req_size   = record->rec.partLength - req->map_offset;
    local_addr = (uintptr_t)record->data->buff;
    chunk = (partition_data_t *)record->data;

    this->state->data_mac->lock_chunk(chunk);
    send_bytes = this->rdma->rdma_write_mof(req->conn, 
                                            local_addr, 
                                            req_size, 
                                            req->remote_addr);

    len = sprintf(ack, "%ld:%ld:%d:", 
                  record->rec.rawLength, 
                  record->rec.partLength, 
                  send_bytes); 

    /* bool prefetch = req_size > send_bytes; */
    shuffle_req_t *prefetch_req = NULL;
    /* if (prefetch) {
        prefetch_req = req;
        prefetch_req->prefetch = true;
    } */

    this->rdma->send_msg(ack, len + 1, (uint64_t)req->peer_wqe,
                         (void *)record->data, req->conn, prefetch_req);
    
    /* testing section */
    /* if (req->map_offset == 0) {
        int reduceid = req->reduceID;
        map<int, int>::iterator iter =
            out_stat.find(reduceid);
        if (iter != out_stat.end()) {
            out_stat[reduceid] = (*iter).second + 1;
        } else {
            out_stat[reduceid] = 1;
        }
        output_stdout("reducer : %d, First mop return: %d",
                      reduceid, out_stat[reduceid]);
    } */
}

void OutputServer::clean_job()
{
    recv_stat.erase(recv_stat.begin(), recv_stat.end());
    out_stat.erase (out_stat.begin(),  out_stat.end());
    output_stdout("JOB OVER *****************************");
}

void OutputServer::comp_outgoing_req(shuffle_req_t *req)
{
    /* FIXME: mark the completion of a fetch request for server */

    /* Server send descriptor
     * 1. mark memory available again
     * 2. increase MOF offset and length
     */
}

/* only for testing */
/* void OutputServer::list_fet_req(const char *path)
{
    char hostname[20];
    gethostname(hostname, 20);

    chdir(path);
    DIR *job_folder = opendir(".");
    struct dirent *job_dir;
    if (job_folder == NULL) {
        fprintf(stderr, "OutputServer: Invalid job folder\n");
        return;
    }

    while (job_dir = readdir(job_folder)) {
        if ((strcmp(job_dir->d_name, ".")  == 0)
             || (strcmp(job_dir->d_name, "..") == 0))
            continue;
        if (job_dir->d_type == DT_DIR) {
            chdir(job_dir->d_name);
            DIR *map_folder = opendir(".");
            if (map_folder == NULL) {
                fprintf(stderr, "OutputServer: Invalid map folder\n");
                return;
            }
            struct dirent *map_dir;
            while ((map_dir = readdir(map_folder))) {
                if (strcmp(map_dir->d_name, ".") == 0
                    || strcmp(map_dir->d_name, "..") == 0)
                    continue;
                if (map_dir->d_type == DT_DIR) {
                    char buffer[200];
                    int len = sprintf(buffer, "* 5:%d:%s:%s:%s:0",
                                      FETCH_MSG,
                                      hostname,
                                      job_dir->d_name,
                                      map_dir->d_name);
                    string str = string(buffer, len);
                    if (str.find("svn") == string::npos) {
                        fprintf(stderr, "%s\n", str.c_str());
                    }
                }
            }
            chdir("..");
        }
    }
    printf("* FINALMERGE\n");
    chdir("../..");
} */

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
