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
#include <errno.h>

#include "MOFServlet.h"
#include "IOUtility.h"
#include "IndexInfo.h"

using namespace std;

#define idx_suffix "/file.out.index"
#define mop_suffix "/file.out"


/* Convert an Octet into an 64-bit integer */
#define OCTET_TO_LONG(b0, b1, b2, b3, b4, b5, b6, b7) \
    (uint64_t((((b0) | 0x0ULL) << 56) | (((b1) | 0x0ULL) << 48) | \
              (((b2) | 0x0ULL) << 40) | (((b3) | 0x0ULL) << 32) | \
              (((b4) | 0x0ULL) << 24) | (((b5) | 0x0ULL) << 16) | \
              (((b6) | 0x0ULL) <<  8) | (((b7) | 0x0ULL) <<  0)))

enum MEM_STAT {FREE, OCCUPIED, INUSE};

bool DataEngine::read_records(partition_table_t* ifile)
{
    size_t writtenBytes=0;
    struct stat file_stat;
    uint8_t *byteRec;
    int fp;

    string idx_fname = ifile->idx_path + idx_suffix;
    if ((fp = open(idx_fname.c_str(), O_RDONLY)) < 0) {
        log(lsERROR, "open idx file %s failed - %m",idx_fname.c_str());
        if ((errno == EMFILE) && (_kernel_fd_rlim.rlim_max)) {
        	log(lsWARN, "Hard rlimit for max open FDs by this process: %lu", _kernel_fd_rlim.rlim_max);
        	log(lsWARN, "Soft rlimit for max open FDs by this process: %lu", _kernel_fd_rlim.rlim_cur);
        }
        return false;
    }

    if (fstat(fp, &file_stat) < 0) {
		log(lsERROR, "get stat failed - filename: %s - %m",idx_fname.c_str());
        return false;
	}

    ifile->total_size = file_stat.st_size;
    byteRec = (uint8_t *) malloc(ifile->total_size);
    if (!byteRec) {
    	log(lsERROR, "failed to allocated memory for reading map index file, file path=%s", ifile->idx_path.c_str());
    	return false;
    }
    writtenBytes = read(fp, byteRec, ifile->total_size);
    close(fp);
    if (writtenBytes <= 0) {
    	log(lsERROR, "read idx file %s failed - %m", idx_fname.c_str());
    	free(byteRec);
        return false;
    }
    ifile->num_entries = writtenBytes / sizeof (index_record_t);
    ifile->records = new (std::nothrow) index_record_t[ifile->num_entries] ; // std::nothrow marks 'new' to not throw exception in case of error , but to return NULL instead
    if (ifile->records) {
    	log(lsERROR, "failed to allocated memory for holding index recordse, file path=%s", ifile->idx_path.c_str());
    	return false;
    }

    for (int i = 0; i < ifile->num_entries; ++i) {
        uint8_t *cp;

        cp = (uint8_t*)(byteRec + i * sizeof(index_record_t));
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
    free(byteRec);
    return true;
}


DataEngine::DataEngine(void *mem, size_t total_size,
                       size_t chunk_size, 
                       supplier_state_t *state,
                       const char *path, int mode, int rdma_buf_size, struct rlimit kernel_fd_rlim)
{

	prepare_tables(mem, total_size, chunk_size, rdma_buf_size);

    INIT_LIST_HEAD(&this->comp_mof_list);

    /* fast mapping from path to partition_table_t */
    this->state_mac = state;
    this->stop = false;
    this->rdma_buf_size = rdma_buf_size;
    this->_kernel_fd_rlim=kernel_fd_rlim;
   

    timespec timeout;
    timeout.tv_nsec=AIOHANDLER_TIMEOUT_IN_NSEC;
    timeout.tv_sec=0;
	output_stdout("AIO: creating new AIOHandler with maxevents=%d , min_nr=%d, nr=%d timeout=%ds %lus",AIOHANDLER_CTX_MAXEVENTS, AIOHANDLER_MIN_NR, AIOHANDLER_NR , timeout.tv_sec, timeout.tv_nsec );
	_aioHandler = new AIOHandler(aio_completion_handler, AIOHANDLER_CTX_MAXEVENTS, AIOHANDLER_MIN_NR , AIOHANDLER_NR, &timeout );


}

void DataEngine::clean_job(const string& jobid)
{
	// clean all index files in-mem
	map<string, partition_table_t*>* jobIfiles = getJobIfiles(jobid);
	if (jobIfiles) {
	    pthread_mutex_lock(&_index_lock);
	    ifile_map.erase(ifile_map.find(jobid));

	    idx_map_iter iter = jobIfiles->begin();
	    while (iter != jobIfiles->end()) {
	       partition_table_t *ifile = iter->second;
	       delete[] ifile->records;
	       delete ifile;
	       iter++;
	    }

	    jobIfiles->erase(jobIfiles->begin(), jobIfiles->end());
	    delete jobIfiles;
	    pthread_mutex_unlock(&_index_lock);
	}

	// clean&close all data files fd&counters, destroy locks
	map<string, fd_counter_t*>* jobFdCounters = getJobFDCounters(jobid);
	if (jobFdCounters) {
		pthread_mutex_lock(&_data_lock);
		_job_fdc_map.erase(_job_fdc_map.find(jobid));

		path_fd_iter iter = jobFdCounters->begin();
		while (iter != jobFdCounters->end()) {
			fd_counter_t* fdc = iter->second;
			// TODO: cancel all aio operations before surprising the kernel with closed FDs to avoid writing ERROR logs entries by AIO thread
			if (fdc->fd)
				close(fdc->fd);
			pthread_mutex_destroy(&fdc->lock);
			delete fdc;
			iter++;
		}

		jobFdCounters->erase(jobFdCounters->begin(), jobFdCounters->end());
		delete jobFdCounters;
		pthread_mutex_unlock(&_data_lock);
	}
}

void 
DataEngine::cleanup_tables()
{
    idx_job_map_iter iter =  ifile_map.begin();
    while (iter != ifile_map.end()) {
    	const string jobid(iter->first);
    	clean_job(jobid);
    }

    pthread_mutex_lock(&this->_chunk_mutex);
    free(this->_chunks);
    pthread_mutex_unlock(&this->_chunk_mutex);


    pthread_mutex_destroy(&this->_data_lock);
    pthread_mutex_destroy(&this->_index_lock);
    pthread_mutex_destroy(&this->_chunk_mutex);
    pthread_cond_destroy(&this->_chunk_cond);
}

void 
DataEngine::prepare_tables(void *mem, 
                           size_t total_size, 
                           size_t chunk_size, 
                           int rdma_buf_size)
{
    char *data=(char*)mem;

    pthread_mutex_init(&this->_data_lock, NULL);
    pthread_mutex_init(&this->_index_lock, NULL);
    pthread_mutex_init(&this->_chunk_mutex, NULL);
    pthread_cond_init(&this->_chunk_cond, NULL);
    INIT_LIST_HEAD(&this->_free_chunks_list);


    pthread_mutex_lock(&this->_chunk_mutex);
    this->_chunks = (chunk_t*)malloc(NETLEV_RDMA_MEM_CHUNKS_NUM * sizeof(chunk_t));
    memset(this->_chunks , 0, NETLEV_RDMA_MEM_CHUNKS_NUM * sizeof(chunk_t));

    log (lsDEBUG, "rdma_buf_size is %d\n", rdma_buf_size);
    for (int i = 0; i < NETLEV_RDMA_MEM_CHUNKS_NUM; ++i) {
        chunk_t *ptr = this->_chunks + i;
        ptr->buff = data + i*(rdma_buf_size + 2*AIO_ALIGNMENT );
        list_add_tail(&ptr->list, &this->_free_chunks_list);
    }
    pthread_mutex_unlock(&this->_chunk_mutex);

}


DataEngine::~DataEngine()
{
    cleanup_tables();
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
            	log(lsDEBUG, "DataEngine: received shuffle request - JOBID=%s REDUCEID=%d offset=%lld", req->m_jobid.c_str(), req->reduceID, req->map_offset);
            	if (process_shuffle_request(req)) {
            		log(lsERROR, "Fail to process shuffle request - JOBID=%s REDUCEID=%d offset=%lld", req->m_jobid.c_str(), req->reduceID, req->map_offset);
            	}
            }
        }

        _aioHandler->submit();


        /* 2.0 Process new MOF files */
        do {
            if (!list_empty(&this->comp_mof_list)) {
				pthread_mutex_lock(&this->_index_lock);
				/* Get the first MOF entry */
				comp = NULL;
				comp = list_entry(this->comp_mof_list.next, typeof(*comp), list);
				list_del(&comp->list);
				if (comp) {
					string jobid(comp->jobid);
					string mapid(comp->mapid);

					rc = read_mof_index_records(jobid, mapid);
					if (rc) {
						log(lsERROR,"failed to read records for MOF's index while processing MOF completion event: jobid=%s, mapid=%s", jobid.c_str(), mapid.c_str());
					}
					free (comp->jobid);
					free (comp->mapid);
					free (comp);
				}
				pthread_mutex_unlock(&this->_index_lock);
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

   	ifile = getIFile(jobid, mapid);
	if (!ifile) { // didn't got MOF completion  yet (mof_downcall_handler wasn't called by JAVA yet for the specific mapid)
		log(lsERROR, "Unexpectedly processing a shuffle request before a MOF completion event was notified by JAVA task: jobid=%s mapid=%s", jobid.c_str(), mapid.c_str());
		return -1;
	}

	if (ifile->total_size) { // inited to 0 , so other value indicates that this method was already called for the specific jobid&mapid
		log(lsERROR, "unexpected call to read mof index records while it was already read");
		return -1;
	}

	if (!read_records(ifile)) {
		log(lsERROR, "failed to read index records for index file path %s  ", ifile->idx_path.c_str() );
		return -1;
	}

	return 0;
}

void DataEngine::add_new_mof(comp_mof_info_t* comp,
                             const char *out_bdir,
                             const char *idx_bdir,
                             const char *user_name)
{
    string jobid(comp->jobid);
    string mapid(comp->mapid);
    string str_out(out_bdir);
    string str_idx(idx_bdir);

    partition_table_t* ifile = new partition_table_t();
    if (!ifile)
    ifile->num_entries=0;
    ifile->records=NULL;
    ifile->total_size=0;
    ifile->idx_path= str_idx + "/" + user_name + "/jobcache/";
    ifile->idx_path += jobid;
    ifile->idx_path += "/";
    ifile->idx_path += mapid;
    ifile->idx_path += "/output";
    ifile->out_path=str_out + "/" + user_name + "/jobcache/";
    ifile->out_path += jobid;
    ifile->out_path += "/";
    ifile->out_path += mapid;
    ifile->out_path += "/output";

    pthread_mutex_lock(&this->_index_lock);
    addIFile(jobid, mapid, ifile);

    log(lsINFO,"new [jobid:%s, mapid:%s]", jobid.c_str(), mapid.c_str());
    log(lsINFO,"dat path: %s", out_bdir);
    log(lsINFO,"idx path: %s", idx_bdir);

    list_add_tail(&comp->list, &this->comp_mof_list);
    pthread_mutex_unlock(&this->_index_lock);
}

partition_table_t* DataEngine::getIFile(const string& jobid, const string& mapid) {
	map<string, partition_table_t*>* jobIfiles = NULL;
	partition_table_t *ifile=NULL;

	jobIfiles=getJobIfiles(jobid);
    if (jobIfiles) {
		idx_map_iter iter = jobIfiles->find(mapid);
		if (iter != jobIfiles->end())
			ifile = iter->second;
	}

    return ifile;
}

map<string, partition_table_t*>* DataEngine::getJobIfiles(const string& jobid) {
	map<string, partition_table_t*>* jobIfiles = NULL;

    idx_job_map_iter iter = ifile_map.find(jobid);
    if (iter != ifile_map.end())
    	jobIfiles = iter->second;

    return jobIfiles;
}

map<string, fd_counter_t*>* DataEngine::getJobFDCounters(const string& jobid) {
	map<string, fd_counter_t*>* jobFdCounters = NULL;

    job_fdc_map_iter iter = _job_fdc_map.find(jobid);
    if (iter != _job_fdc_map.end())
    	jobFdCounters = iter->second;

    return jobFdCounters;
}

fd_counter_t* DataEngine::getFdCounter(const string& jobid, const string& data_path) {
	fd_counter_t* fdcPtr=NULL;

	pthread_mutex_lock(&this->_data_lock);
	map<string, fd_counter_t*>* jobFdCounters=getJobFDCounters(jobid);
	if (!jobFdCounters) {
		jobFdCounters=new map<string, fd_counter_t*>();
	}

	path_fd_iter iter= jobFdCounters->find(data_path);

	if (iter == jobFdCounters->end()) {
		fdcPtr = new fd_counter_t();
		fdcPtr->fd=0;
		fdcPtr->counter=0;
	    pthread_mutex_init(&fdcPtr->lock, NULL);
	    (*jobFdCounters)[data_path]= fdcPtr;
	}
	else {
		fdcPtr=iter->second;
	}
	pthread_mutex_unlock(&this->_data_lock);

	return fdcPtr;
}

bool DataEngine::addIFile(const string &jobid, const string &mapid, partition_table_t* ifile) {
	map<string, partition_table_t*>* jobIfiles = NULL;

    if (getIFile(jobid, mapid)) // already exists
		return false;

	jobIfiles = getJobIfiles(jobid);
	if (!jobIfiles) { // adding first ifile for jobid --> creating mapid to ifile map
		jobIfiles = new map<string, partition_table_t*> ();
		ifile_map[jobid] = jobIfiles;
	}

	(*jobIfiles)[mapid] = ifile;

	return true;
}


int
DataEngine::process_shuffle_request(shuffle_req_t* req) {
    string idx_path;
    string out_path;
    string key = req->m_jobid + req->m_map;
    chunk_t* chunk;
    partition_table_t* ifile=NULL;
    int rc=0;

	pthread_mutex_lock(&this->_index_lock);
	ifile=getIFile(req->m_jobid, req->m_map);

    if (!ifile){ // means that we didn't got MOF completions yet
    	pthread_mutex_unlock(&this->_index_lock);
    	log(lsERROR, "got shuffle request before MOF completion event: REDUCEID=%s", req->m_reduceid.c_str());
    	return -1;
    }

    if (ifile->total_size==0) { // means that DataEngine didn't process the MOF completion yet and the record weren't read to mem.
		log(lsWARN, "process shuffle request while no records were read to mem yet by DataEngine - (suspicion for race between mof completion and shuffle request): REDUCEID=%s", req->m_reduceid.c_str());
		if (read_mof_index_records(req->m_jobid, req->m_map)) {
			pthread_mutex_unlock(&this->_index_lock);
			log(lsERROR,"failed to read records for MOF's index while processing first shuffle request of MOF: jobid=%s, mapid=%s", req->m_jobid.c_str(), req->m_map.c_str());
			return -1;
		}
	}
	pthread_mutex_unlock(&this->_index_lock);

    // in case we have no more chunks to occupy , then we should submit current aio waiting requests before WAITing for a chunk.
	if (list_empty(&this->_free_chunks_list))
    	_aioHandler->submit();

    // this WAITs on cond in case of no more chunks to occupy
	chunk = occupy_chunk();

    if (chunk == NULL) {
        log(lsERROR, "occupy_chunk failed: jobid=%s, map=%s", req->m_jobid.c_str(), req->m_map.c_str());
        return -1;
    }

    rc= aio_read_chunk_data(req, ifile, chunk,  out_path, req->map_offset);

    return rc;
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



int DataEngine::aio_read_chunk_data(shuffle_req_t* req , partition_table_t *ifile, chunk_t* chunk,  const string &out_path, uint64_t map_offset)
{
    int rc=0;

    index_record_t* record=&ifile->records[req->reduceID];
    int64_t offset = record->offset + map_offset;
    size_t read_length = record->partLength - map_offset;
    read_length = (read_length < (size_t)this->rdma_buf_size ) ? read_length : this->rdma_buf_size ;
    log (lsDEBUG, "this->rdma_buf_size inside aio_read_chunk_data is %d\n", this->rdma_buf_size);

    fd_counter_t* fdc=getFdCounter(req->m_jobid, ifile->out_path);
    if (!fdc) {
    	log(lsERROR, "fail to get fd counter jobid=%s out_path=%s", req->m_jobid.c_str(), ifile->out_path.c_str());
    	return -1;
    }
    pthread_mutex_lock(&fdc->lock);
	// avoid frequently re-open file
	if (!fdc->fd) {
		string dat_fname= ifile->out_path + mop_suffix;
		fdc->fd = open(dat_fname.c_str() , O_RDONLY | O_DIRECT);
		if (fdc->fd < 0) {
			log(lsERROR, "open mof %s failed - errno=%m", dat_fname.c_str());
	        if ((errno == EMFILE) && (_kernel_fd_rlim.rlim_max)) {
				log(lsWARN, "Hard rlimit for max open FDs by this process: %lu", _kernel_fd_rlim.rlim_max);
				log(lsWARN, "Soft rlimit for max open FDs by this process: %lu", _kernel_fd_rlim.rlim_cur);
			}
			pthread_mutex_unlock(&fdc->lock);
			return -1;
		}
		fdc->counter=0;
	}

	fdc->counter++; // counts the num of onair aios for this data file
	pthread_mutex_unlock(&fdc->lock);

	req_callback_arg *cb_arg = new req_callback_arg(); // AIOHandler event processor will delete the allocated cb_arg
    cb_arg->fdc=fdc;
	cb_arg->chunk=chunk;
    cb_arg->shreq=req;
    cb_arg->mover=this->state_mac->mover;
    cb_arg->readLength=read_length;
    cb_arg->record=record;
    cb_arg->offsetAligment= (offset & _aioHandler->ALIGMENT_MASK);
    size_t length_for_aio = read_length + 2*AIO_ALIGNMENT - (read_length & _aioHandler->ALIGMENT_MASK);

    long new_offset=offset - cb_arg->offsetAligment;
    rc = _aioHandler->prepare_read(fdc->fd, new_offset  ,length_for_aio   , chunk->buff, cb_arg);

    return rc;
}

int aio_completion_handler(void* data) {
	req_callback_arg *req_cb_arg = (req_callback_arg*)data;

	req_cb_arg->mover->start_outgoing_req(req_cb_arg->shreq, req_cb_arg->record, req_cb_arg->chunk, req_cb_arg->readLength, req_cb_arg->offsetAligment);

	fd_counter_t* fdc=req_cb_arg->fdc;
	pthread_mutex_lock(&fdc->lock);
	fdc->counter--;
	if (!fdc->counter) {
		close(fdc->fd);
	}
	pthread_mutex_unlock(&fdc->lock);

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
