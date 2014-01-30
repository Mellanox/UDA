/*
 * AsyncReaderManager.cc
 *
 *  Created on: Jul 30, 2013
 *      Author: dinal
 */

#include "AsyncReaderManager.h"
#include "../include/IOUtility.h"
#include "../UdaBridge.h"
#include <string.h>
#include "AsyncReaderThread.h"

using namespace std;

AsyncReaderManager::AsyncReaderManager(AbstractReader::Subscriber* _subscriber) : subscriber(_subscriber){

	list<string> disks;
	unsigned int threadsPerDisk = atoi(UdaBridge_invoke_getConfData_callback ("mapred.uda.provider.blocked.threads.per.disk", "1").c_str());
	string data = UdaBridge_invoke_getConfData_callback ("mapred.local.dir", "");
	char dirs[data.length()];
	strcpy(dirs,data.c_str());

	log(lsDEBUG, "AsyncReaderManager threads per disk= %d, disks= %s", threadsPerDisk, dirs);

	char * pch = strtok (dirs,",");
	while (pch != NULL)
	{
		initDiskQueues(string(pch), threadsPerDisk);
		pch = strtok (NULL, ",");
	}

	//init(subscriber, disks, threadsPerDisk);
}

void AsyncReaderManager::initDiskQueues(string diskName, size_t threadsPerDisk)
{
	log(lsDEBUG, "threads per disk = %d, disk diskName = %s", threadsPerDisk, diskName.c_str());
	size_t i;

	//init threads
	for (i = 0; i < threadsPerDisk; i++)
	{
		workers[diskName].push_back(new AsyncReaderThread(diskName, this));
	}

	//init queue structure
	diskNameMap[diskName] = new DiskQueue();
}

void AsyncReaderManager::init(AbstractReader::Subscriber* subscriber, list<string> dirs, size_t threadsPerDisk) {
		size_t i;
		log(lsDEBUG, "threads per disk = %d, num of disks = %d", threadsPerDisk, dirs.size());

		for (list<string>::iterator it=dirs.begin(); it!=dirs.end(); ++it)
		{
			//init threads
			for (i = 0; i < threadsPerDisk; i++)
			{
				workers[*it].push_back(new AsyncReaderThread(*it, this));
			}

			//init queue structure
			log(lsDEBUG, "disk is %s", it->c_str());
			diskNameMap[*it] = new DiskQueue();

		}
}

AsyncReaderManager::~AsyncReaderManager()
{
	//clean worker threads
	 for (map<string,list<AsyncReaderThread *> >::iterator it=workers.begin(); it!=workers.end(); ++it)
	 {
		 for (list<AsyncReaderThread*>::iterator it2=it->second.begin(); it2!=it->second.end(); ++it2)
		 {
			 delete(*it2);
		 }
	 }

	 //clean queues data
	 for (map<string,DiskQueue*>::iterator it=diskNameMap.begin(); it!=diskNameMap.end(); ++it)
	 {
		 DiskQueue* dq = it->second;
		 delete dq;
	 }
}

int AsyncReaderManager::start()
{
	 for (map<string,list<AsyncReaderThread *> >::iterator it=workers.begin(); it!=workers.end(); ++it)
	 {
		 for (list<AsyncReaderThread*>::iterator it2=it->second.begin(); it2!=it->second.end(); ++it2)
		 {
			 (*it2)->start();
		 }
	 }

	return 0;
}

void AsyncReaderManager::insert(ReadRequest* req)
{
	string disk = getDiskFromPath(req->path);
	log(lsDEBUG, "inserting into disk %s, path is %s, diskNameMap.size() %d", disk.c_str(), req->path.c_str(), diskNameMap.size());

	DiskQueue* diskQueue = findDiskQueue(disk);
	if (diskQueue)
	{
		diskQueue->push(req);
	}
	else
	{
		log(lsERROR, "element path is not found!, path = %s, disk = %s",req->path.c_str(), disk.c_str());
		throw new UdaException("element path is not found");
	}
}

int AsyncReaderManager::submit()
{
/*
	log(lsDEBUG, "submit!");
	for (map<string,DiskQueue*>::iterator it=diskNameMap.begin(); it!=diskNameMap.end(); ++it)
	{
		log(lsDEBUG, "AsyncReaderManager::submit, %s", it->first.c_str());
		DiskQueue* dq = it->second;
		if(!dq->empty())
		{
			log(lsDEBUG, "waking up threads on %s", it->first.c_str());
			pthread_cond_broadcast(&((DiskQueue*) it->second)->cond);
		}
	}
//*/
	return 0;
}


string AsyncReaderManager::getDiskFromPath(string path)
{
	size_t index;
	for (map<string,DiskQueue*>::iterator it=diskNameMap.begin(); it!=diskNameMap.end(); ++it)
	{
		if((index = path.find(it->first)) != string::npos)
		{
			return it->first;
		}
	}

	log(lsERROR, "mof disk not found!, %s", path.c_str());

	return "error";
}

void AsyncReaderManager::stop()
{
	 for (map<string,list<AsyncReaderThread *> >::iterator it=workers.begin(); it!=workers.end(); ++it)
	 {
		 list<AsyncReaderThread*> diskReaders = it->second;
		 for (list<AsyncReaderThread*>::iterator it2 = diskReaders.begin(); it2 != diskReaders.end(); ++it2)
		 {
			 AsyncReaderThread * reader = *it2;
			 reader->stop();
		 }
	 }

}
