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

#include <iostream>
#include <pthread.h>
#include "SenderModule/RoceRdmaServer.h"
#include "MofSupplierModule/MofSupplier.h"

typedef  void* (*threadFunc) (void *class_ptr);

/**
 * Start connection listening part of the server
 */
void* serverThreadFunc(void *arg)
{
    RoceRdmaServer *server = (RoceRdmaServer*)arg;
    server->startServer();
}

/**
 * Start request handling part of the server
 */
void* transferThreadFunc(void *arg)
{
    RoceTransferThread *transfer = (RoceTransferThread*)arg;
    transfer->startTransfer();
}

/**
 * launch the thread
 *
 * Input:
 * pthread_t the handler of the thread.
 * handlerFunc the function this thread is going to use.
 * classPtr is the class this thread going to use.
 */
void launchThread(pthread_t *t, threadFunc func, void *classPtr)
{
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_JOINABLE);
    log(lsINFO, "CREATING THREAD"); pthread_create(t, &attr, func, classPtr);
}

int main()
{

    //The thread handler of the connection listening thread.
    pthread_t serverThread;

    //The thread handler of request handling thrread
    pthread_t transferThread;

    //1: launch listening part.
    int rdmaPort = 18515;
    RoceRdmaServer server(rdmaPort);
    launchThread(&serverThread, serverThreadFunc, (void*)&server);

    //2: launch request handling part.
    RoceTransferThread transfer;
    launchThread(&transferThread, transferThreadFunc, (void*)&transfer);
	
    //3: establish the communicate channel between JAVA and C++ processes.
    //will be modified
    int i = 0 ;
    while(true)
    {
      std::cin>>i;
      if(i == 3) break;
    }
}

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
