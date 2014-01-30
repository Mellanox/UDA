/*
 * AsyncReaderThread.cc
 *
 */

#include "AsyncReaderThread.h"
#include "AsyncReaderManager.h"
#include <UdaUtil.h>

using namespace std;

//------------------------------------------------------------------------------
AsyncReaderThread::AsyncReaderThread(string _diskName, AsyncReaderManager* _manager)
	: worker(0) , manager(_manager) , diskName(_diskName) , m_stop(false)
{
	log(lsDEBUG, "AsyncReaderThread ctor - diskName=%s",diskName.c_str());
}

//------------------------------------------------------------------------------
void AsyncReaderThread::start()
{
	log(lsDEBUG, "AsyncReaderThread::starting %s",diskName.c_str());
	pthread_attr_t attr;
	pthread_attr_init(&attr);
	pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_JOINABLE);
	uda_thread_create(&worker, &attr, AsyncReaderThread::asyncReaderThread , this);
}

//------------------------------------------------------------------------------
/* static */ void* AsyncReaderThread::asyncReaderThread(void* _this)
{
	return ((AsyncReaderThread*)_this) -> asyncReaderThread();
}

//------------------------------------------------------------------------------
void* AsyncReaderThread::asyncReaderThread() {

	log(lsINFO, "AsyncReaderThread::asyncReaderThread  %s",diskName.c_str());

	DiskQueue* queueData = manager->findDiskQueue(diskName);
	if(NULL == queueData)
	{
		log(lsERROR, "AsyncReaderThread can't find queue for %s",diskName.c_str());
		throw new UdaException("AsyncReaderThread can't find queue for diskName");
		return 0;
	}

	//
	// forever loop
	//
	for (ReadRequest *req  = NULL; !this->m_stop; ) {
		log(lsTRACE, "%s is working",diskName.c_str());
		queueData->wait_and_pop(req); // wait for new requests
		processShuffleRequest(req);
	}
	return 0;
}


//------------------------------------------------------------------------------
void AsyncReaderThread::processShuffleRequest(ReadRequest* req)
{
	log(lsTRACE, "processShuffleRequest, %s",diskName.c_str());

	ReadCallbackArg _arg(req->fd, req->buff, req->opaque);
	ReadCallbackArg* arg = &_arg;

	if (req->buff == NULL || req->fd == 0) {
		arg = manager->subscriber->prepareRead(req, true);
		if (!arg)
		{
			log(lsERROR, "prepareRead failed");
			delete req;
			return;
		}
	}

	uint64_t size = pread(arg->fd, arg->buff, req->length, req->offset);
	log(lsTRACE, "after read, readLength = %d, size read = %d",req->length, size);
	manager->subscriber->readCallback(arg, 0);
}
