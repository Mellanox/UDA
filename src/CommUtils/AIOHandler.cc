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

#include "IOUtility.h"
#include "AIOHandler.h"
#include <pthread.h>
#include <errno.h>
#include <UdaUtil.h>
#include "UdaBridge.h"

AIOHandler::AIOHandler(AioCallback callback, int ctx_maxevents, long min_nr, long nr, const timespec* timeout) : MAX_EVENTS(ctx_maxevents), MIN_NR(min_nr), NR(nr), GETEVENTS_TIMEOUT(*timeout)
{
	_context=0;
	_callbackProcessorThread=0;
	_callback=callback;
	_stopCallbackProcessor=false;
	_cbRow = new iocb*[MAX_EVENTS];
	_cbRowIndex=0;
	_onAirCounter=0;
	_onAirKernelCounter=0;
	pthread_mutex_init(&_cbRowLock, NULL);
}

int AIOHandler::start()
{
	int rc=0;

	if (_context == 0)
	{

		if ((rc=io_setup(MAX_EVENTS, &_context))) {
			log(lsERROR, "io_setup failure: rc=%d (errno=%m)", rc);
			throw new UdaException("io_setup failure");
			return rc;
		}

		log(lsINFO,"AIO: context was successfully setup");


		log(lsINFO, "AIO: Starting AIO events processor");

		pthread_attr_t attr;
		pthread_attr_init(&attr);
		pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_JOINABLE);
		uda_thread_create(&_callbackProcessorThread, &attr,  (thunk<AIOHandler, &AIOHandler::processEventsCallbacks>), this);
	}

	return rc;
}

AIOHandler::~AIOHandler()
{
	if (_callbackProcessorThread) {
		_stopCallbackProcessor=true;

		pthread_join(_callbackProcessorThread, NULL); log(lsINFO, "THREAD JOINED");

		io_destroy(_context);
	}
	pthread_mutex_destroy(&_cbRowLock);
	delete[] _cbRow;
}

int AIOHandler::prepare_read(int fd, uint64_t fileOffset, size_t sizeToRead, char* dstBuffer, void* callback_arg)
{
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



bool AIOHandler::validateAligment(long fileOffset, size_t size, char* buff)
{
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


int AIOHandler::submit()
{
	int rc=0;

	if (_cbRowIndex != 0) {
		pthread_mutex_lock(&_cbRowLock);
		if (_cbRowIndex != 0) {
			_onAirCounter+=_cbRowIndex;
			_onAirKernelCounter+=_cbRowIndex;
			if ((rc = io_submit(_context, _cbRowIndex, _cbRow)) < 0) {
				log(lsERROR,"io_submit failure: rc=%d", rc);
			}
			else if (rc != _cbRowIndex) {
				log(lsERROR,"io_submit unexpectedly returned only %d submitted operations , instead of %d",rc, _cbRowIndex);
				_onAirCounter-= (_cbRowIndex-rc);
				_onAirKernelCounter-=(_cbRowIndex-rc);
			}
			else {
				log(lsTRACE,"AIO: %d operations submitted. current ONAIR=%d ONAIRKERNEL=%d", rc, _onAirCounter, _onAirKernelCounter);
			}
			_cbRowIndex=0;
		}
		pthread_mutex_unlock(&_cbRowLock);


	}

	return rc;
}

void AIOHandler::processEventsCallbacks()
{
	io_event eventArr[NR];
	int rc=0;
	int callback_rc;
	timespec timeout;
	iocb* cb;
	long long res;
	output_stdout("AIO: Events processor started");
	int aio_status;

	while (!_stopCallbackProcessor) {
		timeout=GETEVENTS_TIMEOUT;

		rc = io_getevents(_context, MIN_NR, NR, eventArr, &timeout);

		if (rc < 0) {
			rc *= -1;

			switch (rc) {

			case EINTR:
				log(lsDEBUG, "io_getevents error: EINTR  Interrupted by a signal handler; see signal(7)");
				// from https://bugzilla.redhat.com/show_bug.cgi?id=768407
				// "Cause: Some libaio calls to disk may be interrupted by the kernel. When this happens, the error message EINTR is returned."
				continue; // Jump to start of while loop and retry the io_getevents()

			case EFAULT:
				log(lsERROR, "io_getevents error: EFAULT Either events or timeout is an invalid pointer");
				break;
			case EINVAL:
				log(lsERROR, "io_getevents error: EINVAL ctx_id is invalid.  min_nr is out of range or nr is out of range");
				break;
			case ENOSYS:
				log(lsERROR, "io_getevents error: EENOSYS io_getevents() is not implemented on this architecture");
				break;
			default:
				log(lsERROR,"io_getevents error: unexpected return code -%d %m",rc);
			}

			throw new UdaException("io_getevents error");
		}
		else if (rc > 0) {

			_onAirKernelCounter-=rc;
			log(lsTRACE,"AIO: got %d events. current ONAIR=%d ONAIRKERNEL=%d", rc, _onAirCounter, _onAirKernelCounter);

			for (int i=0; i < rc ; i++ ) {
				cb = (iocb*)eventArr[i].obj;
				aio_status = 0;
				res=(long long)eventArr[i].res;
				if (res < 0) {
					log(lsERROR,"aio event: completion with error, errno=%lld %m",res);
					aio_status = 1;
					throw new UdaException("aio event: completion with error");
				}
				else if ((uint64_t)res != cb->u.c.nbytes ) { // res is the actual read/writen bytes  , u.c.nbytes is the requested bytes to read/write
					if ((cb->u.c.nbytes - eventArr[i].res) > 2*AIO_ALIGNMENT) {
						// if sub is less then 2*AIO_ALIGNMENT then it is probably as a reasult of alignment and EOF
						// else , it is unexpected.
						log(lsERROR, "aio event: unexpected number of bytes was read/written. requested=%lld actaul=%lld",cb->u.c.nbytes, res);
						aio_status = 1;
						throw new UdaException("aio event: unexpected number of bytes was read/written");
					}
				}

				if ((callback_rc = _callback(eventArr[i].data, aio_status)) != 0 ){
					log(lsERROR,"aio event: callback returned with rc=%d", callback_rc);
				}

				delete cb; // delete the submitted iocb
				// TODO: make a pool of iocb instead of making new and deleteing for each operation

				_onAirCounter--;
				log(lsTRACE,"AIO: after %d events callbacks. current ONAIR=%d ONAIRKERNEL=%d", rc, _onAirCounter, _onAirKernelCounter);
			}
		}
		/*else {
			output_stdout("AIO: process events callbacks - TIMEOUT");
		}*/
	}

	log(lsINFO, "AIO: Events processor stopped");
}

#if LCOV_HYBRID_MERGE_DEAD_CODE
void AIOHandler::setCompletionCallback(AioCallback callback)
{
	pthread_mutex_lock(&_cbRowLock);
	_callback=callback;
	pthread_mutex_unlock(&_cbRowLock);
}

int AIOHandler::prepare_write(int fd, uint64_t fileOffset, size_t sizeToWrite, char* srcBuffer, void* callback_arg)
{
	if (!validateAligment(fileOffset, sizeToWrite, srcBuffer))
		return -1;

	pthread_mutex_lock(&_cbRowLock);
	_cbRow[_cbRowIndex]=new iocb();
	io_prep_pwrite(_cbRow[_cbRowIndex] ,fd, srcBuffer,  sizeToWrite, fileOffset);
	_cbRow[_cbRowIndex]->data = callback_arg;
	_cbRowIndex++;
	pthread_mutex_unlock(&_cbRowLock);

	return 0;
}
#endif
