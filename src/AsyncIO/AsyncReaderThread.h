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

#ifndef BLOCKEDREADER_H_
#define BLOCKEDREADER_H_

#include <pthread.h>
#include <string>

class AsyncReaderManager;
class ReadRequest;

class AsyncReaderThread {

public:
	AsyncReaderThread(std::string _diskName, AsyncReaderManager* _manager);
	void start();
	void stop() {m_stop = true;}
	static void* asyncReaderThread(void*); //thread start

	pthread_t  worker;
	AsyncReaderManager* manager;

private:
	void* asyncReaderThread();
	void processShuffleRequest(ReadRequest* req);

	std::string 	diskName;
	bool m_stop;
};

#endif /* BLOCKEDREADER_H_ */
