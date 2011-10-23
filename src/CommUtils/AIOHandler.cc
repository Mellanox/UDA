/*
 * AIOHandler.cc
 *
 *  Created on: Aug 21, 2011
 *      Author: idanwe
 */

#include "IOUtility.h"
#include "AIOHandler.h"
#include <pthread.h>

#define aio_stderr(str, str_args...)	output_stderr("[%s,%d] " str, __FILE__,__LINE__, ##str_args);
#define aio_stdout(str, str_args...)	output_stdout("[%s,%d] " str, __FILE__,__LINE__, ##str_args);

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
			aio_stderr("io_setup failure: rc=%d (errno=%m)", rc);
			return rc;
		}

		output_stdout("AIO: context was successfully setup");


		output_stdout("AIO: Starting AIO events processor");

		pthread_attr_t attr;
		pthread_attr_init(&attr);
		pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_JOINABLE);
		pthread_create(&_callbackProcessorThread, &attr,  thunk<AIOHandler, &AIOHandler::processEventsCallbacks>, this);
	}

	return rc;

}

AIOHandler::~AIOHandler() {

	if (_callbackProcessorThread) {
		_stopCallbackProcessor=true;

		pthread_join(_callbackProcessorThread, NULL);

		io_destroy(_context);
	}
	free(_cbRow);

}

int AIOHandler::prepare_read(int fd, long fileOffset, size_t sizeToRead, char* dstBuffer, void* callback_arg) {

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

int AIOHandler::prepare_write(int fd, long fileOffset, size_t sizeToWrite, char* srcBuffer, void* callback_arg) {
	throw "NOT Implemented";
}

bool AIOHandler::validateAligment(long fileOffset, size_t size, char* buff) {
	int mod;
	mod = fileOffset&ALIGMENT_MASK;
	if (mod) {
		output_stderr("[%s,%d] AIO parameter is not aligned to %d : filesOffset=%ld",__FILE__,__LINE__, AIO_ALIGNMENT, fileOffset);
		return false;
	}

	mod = size&ALIGMENT_MASK;
	if (mod) {
		output_stderr("[%s,%d] AIO parameter is not aligned to %d : size=%d",__FILE__,__LINE__,AIO_ALIGNMENT, (int)size);
		return false;
	}

	mod = ((long)buff)&ALIGMENT_MASK;
	if (mod) {
		output_stderr("[%s,%d] AIO parameter is not aligned to %d : buff=%ld",__FILE__,__LINE__, AIO_ALIGNMENT, buff);
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
				output_stderr("[%s,%d] io_submit (read) failure: rc=%d",__FILE__,__LINE__, rc);
			}

			if (rc != _cbRowIndex) {
				output_stderr("[%s,%d] io_submit unexpectedly returned only %d submitted operations , instead of %d",__FILE__,__LINE__, rc, _cbRowIndex);
			}

			_cbRowIndex=0;
		}

		if (rc>0) {
			_onAirCounter+=rc;
			output_stdout("AIO: %d operations submitted. current ONAIR=%d", rc, _onAirCounter);
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
			output_stderr("[%s,%d] calling io_getevents failure: rc=%d",__FILE__,__LINE__, rc);

		}
		else if (rc > 0) {


			_onAirCounter-=rc;
			output_stdout("AIO: %d events notified. current ONAIR=%d", rc, _onAirCounter);

			for (int i=0; i < rc ; i++ ) {
				cb = (iocb*)eventArr[i].obj;
				res=(long long)eventArr[i].res;
				if (res < 0) {
					output_stderr("[%s,%d] aio event: completion with error, errno=%lld %m",__FILE__,__LINE__, res);
					exit(-1); // ToDo: Must replace with callback to applciation!!
				}
				else if (res != cb->u.c.nbytes ) { // res is the actual read/writen bytes  , u.c.nbytes is the requested bytes to read/write
					if ((cb->u.c.nbytes - eventArr[i].res) > 2*AIO_ALIGNMENT) {
						// if sub is less then 2*AIO_ALIGNMENT then it is probably as a reasult of alignment and EOF
						// else , it is unexpected.
						output_stderr("[%s,%d] aio event: unexpected number of bytes was read/written. requested=%lld actaul=%lld",__FILE__,__LINE__, cb->u.c.nbytes, res);
						exit(-1); // ToDo: Must replace with callback to applciation!!
					}
				}

				if ((callback_rc = _callback(eventArr[i].data)) != 0 ){
					output_stderr("[%s,%d] aio event: callback returned with rc=%d",__FILE__,__LINE__, callback_rc);
				}

				delete cb; // delete the submitted iocb
				// TODO: make a pool of iocb instead of making new and deleteing for each operation

			}
		}
		/*else {
			output_stdout("AIO: process events callbacks - TIMEOUT");

		}*/


	}

	output_stdout("AIO: Events processor stopped");
}






