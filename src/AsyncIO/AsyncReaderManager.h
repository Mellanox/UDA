#ifndef BLOCKEDREADERMANAGER_H_
#define BLOCKEDREADERMANAGER_H_

#include <pthread.h>
#include <list>
#include <map>
#include <deque>
#include <string>

#include <concurrent_queue.h>
#include "AbstractReader.h"

class AsyncReaderThread;

// ReadRequest(s) on a disk
typedef concurrent_queue<ReadRequest*> DiskQueue;

class AsyncReaderManager : public AbstractReader {

public:
	AsyncReaderManager(AbstractReader::Subscriber* _subscriber);
	void init(AbstractReader::Subscriber* subscriber, std::list<std::string> dirs, size_t threadsPerDisk);
	virtual ~AsyncReaderManager();
	int start();
	void insert(ReadRequest* req);
	int submit();
	void stop();

	DiskQueue* findDiskQueue(const std::string &diskName) {
		std::map<std::string,DiskQueue*>::iterator it = diskNameMap.find(diskName);
		return (it != diskNameMap.end()) ? it->second : NULL;
	}

	AbstractReader::Subscriber* subscriber; //code review: private

private:
	std::string getDiskFromPath(std::string path);
	void initDiskQueues(std::string diskName, size_t threadsPerDisk);

	std::map<std::string,DiskQueue*> diskNameMap;
	std::map<std::string,std::list<AsyncReaderThread *> > workers;
};

#endif /* BLOCKEDREADERMANAGER_H_ */
