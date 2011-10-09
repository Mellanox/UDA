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
        output_stderr("[%s,%d] read idx file failed",__FILE__,__LINE__);
        return -1;
    }

    ifile->first_record = start_index;
    ifile->num_entries = bytes / sizeof (index_record_t);

    for (int i = 0; i < ifile->num_entries; ++i) {
        uint8_t *cp;

        cp = (uint8_t*)(rec + i * sizeof(index_record_t));
        ifile->records[i].offset =
            OCTET_TO_LONG(cp[0], cp[1], cp[2], cp[3], 
                          cp[4], cp[5], cp[6], cp[7]);

        cp = cp + sizeof(uint64_t);
        ifile->records[i].rawLength =
            OCTET_TO_LONG(cp[0], cp[1], cp[2], cp[3], 
                          cp[4], cp[5], cp[6], cp[7]);

        cp = cp + sizeof(uint64_t);
        ifile->records[i].partLength =
            OCTET_TO_LONG(cp[0], cp[1], cp[2], cp[3], 
                          cp[4], cp[5], cp[6], cp[7]);

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
   

    timespec timeout;
    timeout.tv_nsec=AIOHANDLER_TIMEOUT_IN_NSEC;
    timeout.tv_sec=0;
	output_stdout("AIO: creating new AIOHandler with maxevents=%d , min_nr=%d, nr=%d timeout=%ds %lus",AIOHANDLER_CTX_MAXEVENTS, AIOHANDLER_MIN_NR, AIOHANDLER_NR , timeout.tv_sec, timeout.tv_nsec );
	_aioHandler = new AIOHandler(aio_completion_handler, AIOHANDLER_CTX_MAXEVENTS, AIOHANDLER_MIN_NR , AIOHANDLER_NR, &timeout );


}

void DataEngine::clean_job()
{
    pthread_mutex_lock(&index_lock);
    path_map_iter it;
    idx_map_iter iter = ifile_map.begin();
    while (iter != ifile_map.end()) {
       partition_table_t *ifile = (*iter).second;
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

    pthread_mutex_lock(&this->index_lock);
    free(this->ifiles);
    pthread_mutex_unlock(&this->index_lock);

    pthread_mutex_destroy(&this->data_lock);
    pthread_mutex_destroy(&this->index_lock);
    pthread_cond_destroy(&this->data_cond);
    pthread_mutex_destroy(&this->_chunk_mutex);
    pthread_cond_destroy(&this->_chunk_cond);
}

void 
DataEngine::prepare_tables(void *mem, 
                           size_t total_size, 
                           size_t chunk_size) 
{
    char *data=(char*)mem;

    pthread_mutex_init(&this->index_lock, NULL);
    pthread_mutex_init(&this->data_lock, NULL);
    pthread_cond_init(&this->data_cond, NULL);
    INIT_LIST_HEAD(&this->free_ifiles);

    pthread_mutex_init(&this->_chunk_mutex, NULL);
    pthread_cond_init(&this->_chunk_cond, NULL);
    INIT_LIST_HEAD(&this->_free_chunks_list);

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

    pthread_mutex_lock(&this->_chunk_mutex);
    this->_chunks = (chunk_t*)malloc(NETLEV_RDMA_MEM_CHUNKS_NUM * sizeof(chunk_t));
    memset(this->_chunks , 0, NETLEV_RDMA_MEM_CHUNKS_NUM * sizeof(chunk_t));

    for (int i = 0; i < NETLEV_RDMA_MEM_CHUNKS_NUM; ++i) {
        chunk_t *ptr = this->_chunks + i;
        ptr->buff = data + i*(NETLEV_RDMA_MEM_CHUNK_SIZE + 2*AIO_ALIGNMENT );
        list_add_tail(&ptr->list, &this->_free_chunks_list);
    }
    pthread_mutex_unlock(&this->_chunk_mutex);


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
	_aioHandler->start();

    /* Wait on the arrival of new MOF files or shuffle requests */
    while (!this->stop) {
        comp_mof_info_t *comp = NULL;
        shuffle_req_t *req  = NULL;
        int rc=0;

        /* 
         * 1.0 Process new shuffle requests 
         * FIXME 1.5 Start new threads if the queue is long
         */
        while (!list_empty(&state_mac->mover->incoming_req_list)) {
            if (!list_empty(&state_mac->mover->incoming_req_list)) {
                pthread_mutex_lock(&state_mac->mover->in_lock);
                req = list_entry(state_mac->mover->incoming_req_list.next, typeof(*req), list);
                list_del(&req->list);
                pthread_mutex_unlock(&this->state_mac->mover->in_lock);
            } else {
                req = NULL;
            }

            if(req) {
            	output_stdout("DataEngine: received shuffle request");
            	process_shuffle_request(req);
            }
        }

        _aioHandler->submit();

                
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
                string idx_path, out_path;
                string jobid(comp->jobid);
                string mapid(comp->mapid);
                
                rc = read_mof_index_records(jobid, mapid);
                if (rc)
                	output_stderr("[%s,%d] failed to read records for MOF's index while processing MOF completion event: jobid=%s, mapid=%s",__FILE__,__LINE__, jobid, mapid);

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

    output_stdout("DataEngine stopped");
}



int DataEngine::read_mof_index_records(const string &jobid, const string &mapid)
{
    partition_table_t *ifile = NULL;
    bool is_new = false;
    string idx_path, out_path;
    string key = jobid + mapid;
    int rc=0;

    if (!retrieve_path(jobid, mapid, idx_path, out_path)) {
    	output_stderr("[%s,%d] failed to retrieve path",__FILE__,__LINE__);
        return -1; // TODO:  error code
    }

    ifile = getIFile(key, &is_new);

    if (ifile == NULL){
    	output_stderr("[%s,%d] Failed to get iFile (key=%s)",__FILE__,__LINE__, key.c_str());
        return -1; // TODO:  error code
    }
    
    if (!is_new) {
    	output_stderr("[%s,%d] read_mof_index_records: index records for MOF already loaded. idx_path=%s",__FILE__,__LINE__, idx_path.c_str());
        //rc = -1;
    }
    else {
    	rc = read_records(ifile, idx_path, 0);
    	if (rc)
    		output_stderr("[%s,%d] failed to read_records idx_path=%s  ",__FILE__,__LINE__,idx_path.c_str() );
    }

    return rc;
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

partition_table_t* DataEngine::getIFile(string key, bool* is_new) {
    partition_table_t *ifile=NULL;
    *is_new = false;


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
            *is_new = true;
        }
    }

    pthread_mutex_unlock(&index_lock);

    if (!ifile) {
        output_stderr("[%s,%d] no more ifiles", __FILE__,__LINE__);
        ifile = remove_oldest();


        /* re-init index table */
        ifile->total_size = 0;
        ifile->first_record = 0;
        ifile->num_entries = 0;
        *is_new = true;
    }

    return ifile;


}

int
DataEngine::process_shuffle_request(shuffle_req_t* req) {
    bool is_new = false;
    string idx_path;
    string out_path;
    string key = req->m_jobid + req->m_map;
    chunk_t* chunk;
    partition_table_t* ifile;
    int rc=0;

    if (!retrieve_path(req->m_jobid, req->m_map, idx_path, out_path)) {
        output_stderr("[%s,%d] retrieve path failed for fetch reques", __FILE__,__LINE__);
        return -1;
    }

    ifile=getIFile(key, &is_new);

    if (ifile==NULL){
        output_stderr("[%s,%d] failed to get ifile", __FILE__,__LINE__);
        return -2;
    }

    if (is_new) {
    	rc=read_records(ifile, idx_path, 0);
    	if (rc) {
            output_stderr("[%s,%d] failed to read ifile records. rc=%d", __FILE__,__LINE__, rc);
            return -3;
    	}
    }

    if (list_empty(&this->_free_chunks_list))
    	_aioHandler->submit(); // submit current prepared ios before occupy_chunk going to WAIT for chunks

    chunk = occupy_chunk();

    if (chunk == NULL) {
        output_stderr("[%s,%d] failed to occupy chunk (No free chunks)", __FILE__,__LINE__);
        return -4;
    }

    aio_read_chunk_data(req, &ifile->records[req->reduceID], chunk,  out_path, req->map_offset );

    return 0;
}

chunk_t*
DataEngine::occupy_chunk() {
    chunk_t* retval=NULL;

    pthread_mutex_lock(&this->_chunk_mutex);

	if (list_empty(&this->_free_chunks_list)) {
		pthread_cond_wait(&this->_chunk_cond, &this->_chunk_mutex);
	}

	retval= list_entry(this->_free_chunks_list.next, typeof(*retval), list);
	list_del(&retval->list);

	pthread_mutex_unlock(&this->_chunk_mutex);

	return retval;
}

void
DataEngine::release_chunk(chunk_t* chunk) {
    pthread_mutex_lock(&this->_chunk_mutex);
    list_add_tail(&chunk->list, &this->_free_chunks_list);
    pthread_cond_signal(&this->_chunk_cond);
    pthread_mutex_unlock(&this->_chunk_mutex);

}



int DataEngine::aio_read_chunk_data(shuffle_req_t* req , index_record_t *record, chunk_t* chunk,  const string &out_path, uint64_t map_offset)
{
    int rc=0;
    int fd;

    int64_t offset = record->offset + map_offset;
    size_t read_length = record->partLength - map_offset;
    read_length = (read_length < prefetch_chunk_size) ? read_length : prefetch_chunk_size ;

    // fall through to read data from file.out
    string dat_fname = out_path + mop_suffix;

    // avoid frequently re-open file
    fd_map_iter iter = fd_map.find(dat_fname);
    if (iter != fd_map.end()) {
    	fd = iter->second;
    } else {
    	fd = open(dat_fname.c_str(), O_RDONLY | O_DIRECT);
    	if (fd < 0) {
    		output_stderr("[%s,%d] open mof %s failed", __FILE__,__LINE__, dat_fname.c_str());
    		return -1; // TODO: return appropriate rc
    	}
    	fd_map[dat_fname] = fd;
    }


    req_callback_arg *cb_arg = new req_callback_arg(); // AIOHandler event processor will delete the allocated cb_arg
    cb_arg->chunk=chunk;
    cb_arg->shreq=req;
    cb_arg->mover=this->state_mac->mover;
    cb_arg->readLength=read_length;
    cb_arg->record=record;
    cb_arg->offsetAligment= (offset & _aioHandler->ALIGMENT_MASK);
    size_t length_for_aio = read_length + 2*AIO_ALIGNMENT - (read_length & _aioHandler->ALIGMENT_MASK);

    long new_offset=offset - cb_arg->offsetAligment;
    rc = _aioHandler->prepare_read(fd, new_offset  ,length_for_aio   , chunk->buff, cb_arg);

    // exceed maximum number of open fd,
    // then close all previous opened fd
    // TODO: need to provide scalable solution
    if (fd_map.size() > MAX_OPEN_DAT_FILES) {
    	fd_map_iter iter = fd_map.begin();
    	while (iter != fd_map.end()) {
    		close(iter->second);
    		iter++;
    	}
    	fd_map.erase(fd_map.begin(),fd_map.end());
    	output_stderr("[%s,%d] FATAL ERROR: maximum number of open file descriptors exceeded. max=%d",__FILE__,__LINE__, MAX_OPEN_DAT_FILES);
    	exit(1);
    }

    return rc;

}


int aio_completion_handler(void* data) {
	req_callback_arg *req_cb_arg = (req_callback_arg*)data;

	req_cb_arg->mover->start_outgoing_req(req_cb_arg->shreq, req_cb_arg->record, req_cb_arg->chunk, req_cb_arg->readLength, req_cb_arg->offsetAligment);

	delete req_cb_arg->shreq;
    delete req_cb_arg;

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
