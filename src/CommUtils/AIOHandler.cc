/*
 * AIOHandler.cc
 *
 *  Created on: Aug 21, 2011
 *      Author: idanwe
 */

#include "IOUtility.h"
#include "AIOHandler.h"
#include <pthread.h>
#include <errno.h>

AIOHandler::AIOHandler(AioCallback callback, int ctx_maxevents, long min_nr, long nr, const timespec* timeout) : MAX_EVENTS(ctx_maxevents), MIN_NR(min_nr), NR(nr), GETEVENTS_TIMEOUT(*timeout)
{
	_context=0;
	_callbackProcessorThread=0;
	_callback=callback;
	_stopCallbackProcessor=false;
	_cbRow = new iocb*[MAX_EVENTS];
	_cbRowIndex=0;
	_onAirCounter=0;
	pthread_mutex_init(&_cbRowLock, NULL);
}

int AIOHandler::start() {
	int rc=0;

	if (_context == 0)
	{

		if ((rc=io_setup(MAX_EVENTS, &_context))) {
			log(lsFATAL, "io_setup failure: rc=%d (errno=%m)", rc);
			return rc;
		}

		log(lsINFO,"AIO: context was successfully setup");


		log(lsINFO, "AIO: Starting AIO events processor");

		pthread_attr_t attr;
		pthread_attr_init(&attr);
		pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_JOINABLE);
		log(lsINFO, "CREATING THREAD"); pthread_create(&_callbackProcessorThread, &attr,  thunk<AIOHandler, &AIOHandler::processEventsCallbacks>, this);
	}

	return rc;

}

AIOHandler::~AIOHandler() {

	if (_callbackProcessorThread) {
		_stopCallbackProcessor=true;

		pthread_join(_callbackProcessorThread, NULL); log(lsINFO, "THREAD JOINED");

		io_destroy(_context);
	}
	free(_cbRow);

}

int AIOHandler::prepare_read(int fd, uint64_t fileOffset, size_t sizeToRead, char* dstBuffer, void* callback_arg) {

	if (!validateAligment(fileOffset, sizeToRead, dstBuffer))
		return -1;

	pthread_mutex_lock(&_cbRowLock);
	_cbRow[_cbRowIndex]=new iocb();
	io_prep_pread(_cbRow[_cbRowIndex] ,fd, dstBuffer,  sizeToRead, fileOffset);
	_cbRow[_cbRowIndex]->data = callback_arg;
	_cbRowIndex++;
	pthread_mutex_unlock(&_cbRowLock);

	return 0;
}

int AIOHandler::prepare_write(int fd, uint64_t fileOffset, size_t sizeToWrite, char* srcBuffer, void* callback_arg) {
	throw "NOT Implemented";
}

bool AIOHandler::validateAligment(long fileOffset, size_t size, char* buff) {
	int mod;
	mod = fileOffset&ALIGMENT_MASK;
	if (mod) {
		log(lsERROR,"AIO parameter is not aligned to %d : filesOffset=%ld",AIO_ALIGNMENT, fileOffset);
		return false;
	}

	mod = size&ALIGMENT_MASK;
	if (mod) {
		log(lsERROR, "AIO parameter is not aligned to %d : size=%d",AIO_ALIGNMENT, (int)size);
		return false;
	}

	mod = ((long)buff)&ALIGMENT_MASK;
	if (mod) {
		log(lsERROR, "AIO parameter is not aligned to %d : buff=%ld", AIO_ALIGNMENT, buff);
		return false;
	}

	return true;
}


int AIOHandler::submit() {
	int rc=0;

	if (_cbRowIndex != 0) {
		pthread_mutex_lock(&_cbRowLock);
		if (_cbRowIndex != 0) {
			if ((rc = io_submit(_context, _cbRowIndex, _cbRow)) <= 0) {
				log(lsERROR,"io_submit (read) failure: rc=%d", rc);
			}

			if (rc != _cbRowIndex) {
				log(lsERROR,"io_submit unexpectedly returned only %d submitted operations , instead of %d",rc, _cbRowIndex);
			}

			_cbRowIndex=0;
		}

		if (rc>0) {
			_onAirCounter+=rc;
			log(lsTRACE,"AIO: %d operations submitted. current ONAIR=%d", rc, _onAirCounter);
		}
		pthread_mutex_unlock(&_cbRowLock);


	}

	return rc;

}


void AIOHandler::processEventsCallbacks() {
	io_event eventArr[NR];
	int rc=0;
	int callback_rc;
	timespec timeout;
	iocb* cb;
	long long res;
	output_stdout("AIO: Events processor started");

	while(!_stopCallbackProcessor) {
		timeout=GETEVENTS_TIMEOUT;

		rc = io_getevents(_context, MIN_NR, NR, eventArr, &timeout );

		if (rc < 0) {
			rc *= -1;
			
			switch (rc) {
				case EFAULT:
					log(lsFATAL, "io_getevents error: EFAULT Either events or timeout is an invalid pointer");
					break;
				case EINVAL:
					log(lsFATAL, "io_getevents error: EINVAL ctx_id is invalid.  min_nr is out of range or nr is out of range");
					break;
				case EINTR:
					log(lsFATAL, "io_getevents error: EINTR  Interrupted by a signal handler; see signal(7)");
					break;
				case ENOSYS:
					log(lsFATAL, "io_getevents error: EENOSYS io_getevents() is not implemented on this architecture");
					break;
				default:
					log(lsERROR,"io_getevents error: unexpected return code -%d %m",rc);		
			}
			
			exit(-1); // TODO
		}
		else if (rc > 0) {


			_onAirCounter-=rc;
			log(lsTRACE, "AIO: %d events notified. current ONAIR=%d", rc, _onAirCounter);

			for (int i=0; i < rc ; i++ ) {
				cb = (iocb*)eventArr[i].obj;
				res=(long long)eventArr[i].res;
				if (res < 0) {
					log(lsFATAL,"aio event: completion with error, errno=%lld %m",res);
					exit(-1); // ToDo: Must replace with callback to applciation!!
				}
				else if ((uint64_t)res != cb->u.c.nbytes ) { // res is the actual read/writen bytes  , u.c.nbytes is the requested bytes to read/write
					if ((cb->u.c.nbytes - eventArr[i].res) > 2*AIO_ALIGNMENT) {
						// if sub is less then 2*AIO_ALIGNMENT then it is probably as a reasult of alignment and EOF
						// else , it is unexpected.
						log(lsFATAL, "aio event: unexpected number of bytes was read/written. requested=%lld actaul=%lld",cb->u.c.nbytes, res);
						exit(-1); // ToDo: Must replace with callback to applciation!!
					}
				}

				if ((callback_rc = _callback(eventArr[i].data)) != 0 ){
					log(lsERROR,"aio event: callback returned with rc=%d", callback_rc);
				}

				delete cb; // delete the submitted iocb
				// TODO: make a pool of iocb instead of making new and deleteing for each operation

			}
		}
		/*else {
			output_stdout("AIO: process events callbacks - TIMEOUT");

		}*/


	}

	log(lsINFO, "AIO: Events processor stopped");
}






