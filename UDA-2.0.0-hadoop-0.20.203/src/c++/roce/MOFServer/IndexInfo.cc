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

#include <fcntl.h>
#include <unistd.h>
#include <sys/time.h>

#include "MOFServlet.h"
#include "IOUtility.h"
#include "IndexInfo.h"

using namespace std;

#define idx_suffix "/file.out.index"
#define mop_suffix "/file.out"
#define prefetch_chunk_size  NETLEV_RDMA_MEM_CHUNK_SIZE  

/* Convert an Octet into an 64-bit integer */
#define OCTET_TO_LONG(b0, b1, b2, b3, b4, b5, b6, b7) \
    (uint64_t((((b0) | 0x0ULL) << 56) | (((b1) | 0x0ULL) << 48) | \
              (((b2) | 0x0ULL) << 40) | (((b3) | 0x0ULL) << 32) | \
              (((b4) | 0x0ULL) << 24) | (((b5) | 0x0ULL) << 16) | \
              (((b6) | 0x0ULL) <<  8) | (((b7) | 0x0ULL) <<  0)))

enum MEM_STAT {FREE, OCCUPIED, INUSE};

int DataEngine::read_records(partition_table_t *ifile, 
                             const string &idx_path,
                             int start_index)
{
    size_t offset, to_read, bytes;
    struct stat file_stat;
    uint8_t *rec;
    int fp;

    string idx_fname = idx_path + idx_suffix; 
    if ((fp = open(idx_fname.c_str(), O_RDONLY)) < 0) { 
        output_stderr("[%s,%d] open idx file %s failed",
                      __FILE__,__LINE__,
                      idx_fname.c_str());
        return -1;
    }

    /* avoid repeat read */
    if (ifile->total_size == 0) {
        if (fstat(fp, &file_stat) < 0) {
            output_stderr("[%s,%d] get stat failed",
                          __FILE__,__LINE__);
            return -1;
        }
        ifile->total_size = file_stat.st_size;
    }

    /* 
     * XXX: get the number of partitions. 
     * The suffix for checksum is ignored.
     * Assumption: checksum is smaller than IndexRecord
     */
    offset = start_index * sizeof (index_record_t);
    to_read = NETLEV_MIN ((ifile->total_size - offset), 
                          (sizeof(index_record_t) * MAX_RECORDS_PER_MOF));

    rec = (uint8_t *) malloc(to_read);
    lseek(fp, offset, SEEK_SET);
    bytes = read(fp, rec, to_read);
    close(fp);
    if (bytes < 0) {
        output_stderr("[%s,%d] read idx file failed",
                      __FILE__,__LINE__);
        return -1;
    }

    ifile->first_record = start_index;
    ifile->num_entries = bytes / sizeof (index_record_t);

    for (int i = 0; i < ifile->num_entries; ++i) {
        uint8_t *cp;

        cp = (uint8_t*)(rec + i * sizeof(index_record_t));
        ifile->records[i].rec.offset =
            OCTET_TO_LONG(cp[0], cp[1], cp[2], cp[3], 
                          cp[4], cp[5], cp[6], cp[7]);

        cp = cp + sizeof(uint64_t);
        ifile->records[i].rec.rawLength =
            OCTET_TO_LONG(cp[0], cp[1], cp[2], cp[3], 
                          cp[4], cp[5], cp[6], cp[7]);

        cp = cp + sizeof(uint64_t);
        ifile->records[i].rec.partLength =
            OCTET_TO_LONG(cp[0], cp[1], cp[2], cp[3], 
                          cp[4], cp[5], cp[6], cp[7]);

        ifile->records[i].data = NULL;
    }
    free(rec);
    return 0;
}


DataEngine::DataEngine(void *mem, size_t total_size,
                       size_t chunk_size, 
                       supplier_state_t *state,
                       const char *path, int mode)
{
    /* XXX:
     * Data Engine should hold the following tables
     * MAX_MOFS_INCACHE index files (currently 1024)
     * MAX_RECORDS_PER_MOF (currently 128) 
     */
    prepare_tables(mem, total_size, chunk_size);

    INIT_LIST_HEAD(&this->comp_mof_list);
    /* fast mapping from path to partition_table_t */
    this->state_mac = state;
    this->stop = false;
   
    /* for testing 
    if (mode == STANDALONE){
        this->base_path = strdup(path);
    } */

}

void DataEngine::clean_job()
{
    pthread_mutex_lock(&index_lock);
    path_map_iter it;
    idx_map_iter iter = ifile_map.begin();
    while (iter != ifile_map.end()) {
       partition_table_t *ifile = (*iter).second;
       for (int rc = 0; rc < MAX_RECORDS_PER_MOF; ++rc) {
          partition_record_t *record = &ifile->records[rc]; 
          if (record) {
              partition_data_t *chunk = record->data;
              if (chunk) {
                  chunk->status = FREE;
                  chunk->rec = NULL;
                  chunk->map_offset = -1;
                  memset(chunk->buff, 0, chunk_size);
                  list_add_tail(&chunk->list, &free_chunks); 
              }
              record->data = NULL;
          }
       }
       /* clean up ifiles */
       memset(ifile, 0, sizeof(partition_table_t));
       list_add_tail(&ifile->list, &free_ifiles);   
       iter++;
    }   
    ifile_map.erase(ifile_map.begin(), 
                    ifile_map.end());
    pthread_mutex_unlock(&index_lock);

    /* close all files */
    fd_map_iter fd_iter = fd_map.begin();
    while (fd_iter != fd_map.end()) {
        int fd = (*fd_iter).second;
        close(fd);
        ++fd_iter;
    }  
    fd_map.erase(fd_map.begin(),
                 fd_map.end());

    pthread_mutex_lock(&data_lock);
    /* clean all pathes */

    for ( it=mof_path.begin() ; it != mof_path.end(); it++ ){
        free (it->second.user_name);
    }
     


    mof_path.erase(mof_path.begin(),
                   mof_path.end());
    pthread_mutex_unlock(&data_lock);
}

void 
DataEngine::cleanup_tables()
{
    pthread_mutex_lock(&this->data_lock);
    free(this->chunks);
    pthread_mutex_unlock(&this->data_lock);

    pthread_mutex_lock(&this->index_lock);
    free(this->ifiles);
    pthread_mutex_unlock(&this->index_lock);

    pthread_mutex_destroy(&this->data_lock);
    pthread_mutex_destroy(&this->index_lock);
    pthread_cond_destroy(&this->data_cond);
}

void 
DataEngine::prepare_tables(void *mem, 
                           size_t total_size, 
                           size_t chunk_size) 
{
    char *data;

    pthread_mutex_init(&this->index_lock, NULL);
    pthread_mutex_init(&this->data_lock, NULL);
    pthread_cond_init(&this->data_cond, NULL);
    INIT_LIST_HEAD(&this->free_chunks);
    INIT_LIST_HEAD(&this->free_ifiles);

    pthread_mutex_lock(&this->index_lock);
    this->ifiles = (partition_table_t*)
        malloc(NETLEV_MAX_MOFS_INCACHE * sizeof(partition_table_t));
    memset(this->ifiles, 0, 
            NETLEV_MAX_MOFS_INCACHE * sizeof(partition_table_t));

    for (int i = 0; i < NETLEV_MAX_MOFS_INCACHE; ++i) {
        partition_table_t *ptr = this->ifiles + i;
        list_add_tail(&ptr->list, &free_ifiles);
    }
    pthread_mutex_unlock(&this->index_lock);

    /* Get a table of data chunks for partitions */
    pthread_mutex_lock(&this->data_lock);
    this->num_chunks = total_size / chunk_size;
    this->chunk_size = chunk_size;
    this->chunks = (partition_data_t*)
        malloc(num_chunks * sizeof (partition_data_t));

    data = (char *)mem;
    for (int i = 0; i < num_chunks; i++) {
        partition_data_t *tmp = this->chunks + i;
        tmp->status = FREE;
        tmp->map_offset = -1; 
        tmp->rec = NULL;
        tmp->buff = data + chunk_size * i;
        list_add_tail(&tmp->list, &free_chunks);
    }
    pthread_mutex_unlock(&this->data_lock);
}


DataEngine::~DataEngine()
{
    cleanup_tables();
    //free(this->base_path);
    fd_map_iter iter = fd_map.begin();
    while (iter != fd_map.end()) {
        close(iter->second);
        iter++;
    }
}

/**
 * 1. DataEngine pops out requests from global queue 
 * 2. Check the cache
 * 3. Call RdmaServer to send MOF. 
 */
void 
DataEngine::start()
{
    /* Wait on the arrival of new MOF files or shuffle requests */
    while (!this->stop) {
        comp_mof_info_t *comp = NULL;
        shuffle_req_t *req  = NULL;

        /* 
         * 1.0 Process new shuffle requests 
         * FIXME 1.5 Start new threads if the queue is long
         */
        do {
            if (!list_empty(&state_mac->mover->incoming_req_list)) {
                pthread_mutex_lock(&state_mac->mover->in_lock);
                req = list_entry(state_mac->mover->incoming_req_list.next, 
                        typeof(*req), list);
                list_del(&req->list);
                pthread_mutex_unlock(&this->state_mac->mover->in_lock);
            } else {
                req = NULL;
            }

            if(req) {
                push_shuffle_req(req);
            }
        } while (!list_empty(&state_mac->mover->incoming_req_list));

                
        /* 2.0 Process new MOF files */
        do {
            if (!list_empty(&this->comp_mof_list)) {
                pthread_mutex_lock(&this->index_lock);
                /* Get the first MOF entry */
                comp = list_entry(this->comp_mof_list.next, 
                                  typeof(*comp), list);
                list_del(&comp->list);
                pthread_mutex_unlock(&this->index_lock);
            } else {
                comp = NULL;
            }

            if (comp) {
                /*XXX: we need to use char* here to 
                  avoid multiple string addition */
                string idx_path, out_path;
                string jobid(comp->jobid);
                string mapid(comp->mapid);
                if (retrieve_path(jobid, mapid, idx_path, out_path)) {

                    string key = jobid + mapid;
                    /* prefetch the MOF index records and data chunks */
                    this->prefetch_mof(idx_path, out_path,      
                                       key, 0, 0, true);
                } else {
                    output_stderr("retrieve path failed for prefetch");
                }
                
                free (comp->jobid);
                free (comp->mapid);
                free (comp);
            }

        } while (!list_empty(&this->comp_mof_list)); 

        /* check if there is a new incoming shuffle req */
        pthread_mutex_lock(&state_mac->mover->in_lock);
        if (!list_empty(&state_mac->mover->incoming_req_list)) {
            pthread_mutex_unlock(&state_mac->mover->in_lock);
            continue;
        }
        pthread_cond_wait(&state_mac->mover->in_cond,
                          &state_mac->mover->in_lock);
        pthread_mutex_unlock(&state_mac->mover->in_lock);        
    } 
}

int 
DataEngine::push_shuffle_req(shuffle_req_t *sreq)
{
    partition_record_t *record = NULL;
    if (!sreq->prefetch) {
        record = get_record_by_path(sreq->m_jobid,
                                    sreq->m_map, 
                                    sreq->reduceID,
                                    sreq->map_offset);
        if (record) {
            lock_chunk(record->data);
            this->state_mac->mover->start_outgoing_req(sreq, record);
            delete sreq;
        }
    } else {
        /* suppose need prefetch */
        /* record = get_record_by_path(sreq->m_jobid,
                                    sreq->m_map, 
                                    sreq->reduceID,
                                    sreq->map_offset + prefetch_chunk_size);
        delete sreq; */
    }
    return 0;
}

partition_table_t*
DataEngine::prefetch_mof(const string &idx_path, 
                         const string &out_path,
                         const string &key, int index,
                         uint64_t map_offset,
                         bool prefetch_all)
{
    partition_table_t *ifile = NULL;
    bool is_new = false;

    pthread_mutex_lock(&index_lock);

    idx_map_iter iter = ifile_map.find(key);
    if (iter != ifile_map.end()) {
        ifile = iter->second; 
    } else {
        if (!list_empty(&free_ifiles)) {
            ifile = list_entry(free_ifiles.next,typeof(*ifile), list);
            list_del(&ifile->list);
            ifile_map[key] = ifile;
            
            /* init index table */
            ifile->total_size = 0;
            ifile->first_record = 0;
            ifile->num_entries = 0;
            is_new = false;
        }
    }
    
    pthread_mutex_unlock(&index_lock);

    if (!ifile) {
        output_stderr("[%s,%d] no more ifiles",
                      __FILE__,__LINE__);
        ifile = remove_oldest(); 

        /* XXX: free all the data chunks */
        pthread_mutex_lock(&this->data_lock);
        for (int i = 0; i < ifile->num_entries; i++) {
            partition_data_t *chunk = ifile->records[i].data;
            if (chunk) {
                /* return data chunk */
                chunk->status = FREE;
                chunk->map_offset = -1; 
                chunk->rec = NULL;
                list_add_tail(&chunk->list, &free_chunks);
            }
        } 
        pthread_mutex_unlock(&this->data_lock);
           
        /* re-init index table */ 
        ifile->total_size = 0;
        ifile->first_record = 0;
        ifile->num_entries = 0;
        is_new = true;
    }

    int l = ifile->first_record;
    int h = l + ifile->num_entries;
    if (is_new || (!is_new && (index < l || index >= h))) {
        if (read_records(ifile, idx_path, index)) {
            return NULL;
        }
    }
    
    if (prefetch_all) {
       /* prefetch data chunks for a file
        * NETLEV_RDMA_MEM_CHUNK_SIZE per record */
        int num = ifile->num_entries;
        for (int i = 0; i < num; ++i) { 
            read_chunk_data(ifile, out_path, i, map_offset, 
                            prefetch_chunk_size);
        }
    } else {
        int target = index - ifile->first_record;
        read_chunk_data(ifile, out_path, target, map_offset, 
                        prefetch_chunk_size);
    }
    return ifile;
}

/*unlock this chunk when RDMA Write is done*/
void DataEngine::unlock_chunk(partition_data_t *chunk)
{
    chunk->status = OCCUPIED;
}

/*lock this chunk when we are doing RDMA Write operation*/
void 
DataEngine::lock_chunk(partition_data_t *chunk)
{
    chunk->status = INUSE;

}


partition_data_t *DataEngine::get_new_chunk()
{
    partition_data_t *chunk = NULL;

    if (list_empty(&this->free_chunks)) {
        output_stderr("[%s,%d] no more data chunks",
                      __FILE__,__LINE__);
        /**
         * FIXME: (urgent) how to find the available data chunk
         */
    } else {
        chunk = list_entry(free_chunks.next, typeof(*chunk), list);
        list_del(&chunk->list);
    }
    return chunk;
}

void 
DataEngine::read_chunk_data(partition_table_t *ifile,
                            const string &out_path,
                            int record_index, 
                            uint64_t map_offset,
                            uint32_t length)
{
    /* XXX: assume index record is in the table */
    partition_record_t *rec;
    partition_data_t   *chunk;

    int64_t offset;
    uint64_t read_length;
    int fd;

    rec = &ifile->records[record_index];
    offset = rec->rec.offset + map_offset;
    length = (length > prefetch_chunk_size ? prefetch_chunk_size : length);
    read_length = rec->rec.partLength - map_offset;
    if(read_length < length)
        length = read_length;
   
    chunk = rec->data;

    if (!chunk) {
        chunk = get_new_chunk();
        chunk->status = OCCUPIED;
        chunk->map_offset = -1; /* Force it to read data */
        rec->data = chunk; 
    } else {
        /* already fetched in previous pre-fetch */
        if (chunk->map_offset == map_offset) {
            return;
        }
    }

    // fall through to read data from file.out
    string dat_fname = out_path + mop_suffix; 

    // avoid frequently re-open file
    fd_map_iter iter = fd_map.find(dat_fname);
    if (iter != fd_map.end()) {
        fd = iter->second;
    } else {
        fd = open(dat_fname.c_str(), O_RDONLY);
        if (fd < 0) {
            output_stderr("[%s,%d] open mof %s failed",
                          __FILE__,__LINE__,
                          dat_fname.c_str());
            return;
        }        
        fd_map[dat_fname] = fd;
    }

    if (map_offset > rec->rec.partLength) {
        output_stderr("[%s,%d] bad shuffle request",
                      __FILE__,__LINE__);
        return;
    }

    // jump to the correct start position from begining
    lseek(fd, offset, SEEK_SET);
    read(fd, chunk->buff, length);
    chunk->map_offset = map_offset; 

    // exceed maximum number of open fd,
    // then close all previous opened fd 
    if (fd_map.size() > MAX_OPEN_DAT_FILES) {
        fd_map_iter iter = fd_map.begin();
        while (iter != fd_map.end()) {
            close(iter->second);
            iter++;
        }
        fd_map.erase(fd_map.begin(),fd_map.end());
    }
}

bool DataEngine::retrieve_path(const string &jobid,
                               const string &mapid,
                               string &idx_path,
                               string &out_path) 
{
    string key(jobid);
    key += mapid;

    pthread_mutex_lock(&data_lock); 
    path_map_iter iter = mof_path.find(key);
    if (iter == mof_path.end()) {
        output_stderr("%s", "retrieve path error");
        pthread_mutex_unlock(&data_lock);
        return false;
    } else {
        path_info p_i = iter->second;       

        idx_path = spindles[p_i.idx_pos] + "/" + p_i.user_name + "/jobcache/";
        idx_path += jobid;
        idx_path += "/";
        idx_path += mapid;
        idx_path += "/output";
 
        out_path = spindles[p_i.out_pos] + "/" + p_i.user_name + "/jobcache/";
        out_path += jobid;
        out_path += "/";
        out_path += mapid;
        out_path += "/output";
    } 
    pthread_mutex_unlock(&data_lock);
    return true;
}

void DataEngine::add_new_mof(const char *jobid, 
                             const char *mapid,
                             const char *out_bdir,
                             const char *idx_bdir,
                             const char *user_name)
{
    int out_pos = -1;
    int idx_pos = -1;

    string key(jobid);
    key += mapid;
    
    string str_out(out_bdir);
    string str_idx(idx_bdir);
    
    pthread_mutex_lock(&data_lock);
    
    for (int s = 0; s < (int) spindles.size(); ++s) {
      if (out_pos < 0 && spindles[s].compare(str_out) == 0) {
          out_pos = s;
      }
      if (idx_pos < 0 && spindles[s].compare(str_idx) == 0) {
          idx_pos = s;
      }    
    }

    if (out_pos < 0) {
        spindles.push_back(str_out);
        out_pos = spindles.size()-1;
    }

    if (idx_pos < 0) {
        if (spindles[spindles.size()-1].compare(str_idx) != 0) {
            spindles.push_back(str_idx);
        }
        idx_pos = spindles.size()-1;
    }
   
    path_info p_i;
    p_i.idx_pos = idx_pos;
    p_i.out_pos=out_pos;
    p_i.user_name = strdup(user_name);

    mof_path[key] = p_i;


    output_stdout("new [jobid:%s, mapid:%s]", jobid, mapid);
    output_stdout("dat path: %s", out_bdir);
    output_stdout("idx path: %s", idx_bdir);

    pthread_mutex_unlock(&data_lock);
}


/* fill in the cache if it is available */
partition_record_t*
DataEngine::get_record_by_path(const string &jobid, 
                               const string &mapid, 
                               int reduceid, 
                               uint64_t map_offset)
{
    partition_table_t  *ifile;
    
    string idx_path; 
    string out_path;

    if (!retrieve_path(jobid, mapid, 
                       idx_path,
                       out_path)) {
        output_stderr("retrieve path failed for fetch request");
        return NULL;
    }
    
    string key = jobid + mapid;
    ifile = prefetch_mof(idx_path,
                         out_path,  
                         key, reduceid, 
                         map_offset, false);
    ifile->used_times++;

    return &ifile->records[reduceid-ifile->first_record];
}

partition_table_t*
DataEngine::remove_oldest()
{
    idx_map_iter curIter;
    idx_map_iter minIter;
    minIter = curIter = ifile_map.begin();
    curIter++;

    while (curIter != ifile_map.end()) {
        if ((curIter->second)->used_times > 
            (minIter->second)->used_times) {
            minIter = curIter;
        }
        curIter++;
    }

    partition_table_t *ifile = minIter->second;
    ifile_map.erase(minIter);
    return ifile;
}

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
*/
