
#ifndef AIO_HANDLER_H
#define AIO_HANDLER_H 1

#include <libaio.h>
#include <fcntl.h>
#include <stdio.h>

#define AIO_ALIGNMENT_EXPO	(12) // alignment to 4k
#define AIO_ALIGNMENT 		(1<<AIO_ALIGNMENT_EXPO)

typedef int (*AioCallback)(void*);

template<class T, void(T::*mem_fn)()>
void* thunk(void* p)
{
	(static_cast<T*>(p)->*mem_fn)();
	return 0;
}


class AIOHandler {
private:
	io_context_t	_context;
	pthread_t		_callbackProcessorThread;
	AioCallback 	_callback;
	bool			_stopCallbackProcessor;
	iocb**			_cbRow;
	int				_cbRowIndex;
	pthread_mutex_t	_cbRowLock;
	int	_onAirKernelCounter;
	int _onAirCounter;


	// thread function for processing aio events callbacks .
	void processEventsCallbacks();

	// returns TRUE is fileOffset, size AND buff are aligned to SECTOR_SIZE
	bool validateAligment(long fileOffset, size_t size, char* buff);

public:
	static const int 		ALIGMENT_MASK = ~(-1 << AIO_ALIGNMENT_EXPO);

	const int		MAX_EVENTS;
	const long		MIN_NR;
	const long		NR;
	const timespec	GETEVENTS_TIMEOUT;

	/* @param AioCallback callback the callback function to be executed for each processed event.
	 * @param int ctx_maxevents the maximum number of events for the aio context to be capable to receive on cq
	 * @param int min_nr the minimum events to read from the completion queue of the AIO context on each 'getevents' call
	 * @param int nr read up to nr events from the completion queue of the AIO context on each 'getevents' call
	 * @param timespec timeout timeout for blocking wait on getevents from context
	 */
	AIOHandler(AioCallback callback, int ctx_maxevents, long min_nr, long nr, const timespec* timeout);

	~AIOHandler();


	/* prepare aio read request that will be submitted on next submit() call.
	 * @param int fd File Descriptor to read from.
	 * @param char* buffer The buffer for writing the read data.
	 * @param long fileOffset The offset on filename
	 * @param long sizeToRead The size to read from filename
	 * @param void* arg The argument which will be delivered to callback when it will be invoked
	 * @param void* callback the callback function which will be executed when event will notified by aio context that the submitted request was finished.
	 * */
	int prepare_read(int fd, uint64_t fileOffset, size_t sizeToRead, char* dstBuffer, void* callback_arg /*, bool create_callback_thread=false*/ );


	// TODO:
	int prepare_write(int fd, uint64_t fileOffset, size_t sizeToWrite, char* srcBuffer, void* callback_arg);

	/* submits prepared aio operations
	 * returns the number of submitted aio operations or <0 for error
	 */
	int submit();


	// initializes aio context and starts the thread for processing submitted aio events callbacks
	// D'tor will stop the thread.
	int start();

	/*
	 * Set the function method which will be called for each aio completion event
	 */
	void setCompletionCallback(AioCallback callback);

	/*
	 * return the current number of submitted AIOs that wasn't completed yet AND it's callback wasn't processed yet
	 */
	int getOnAir() { return _onAirCounter; }


};




#endif
