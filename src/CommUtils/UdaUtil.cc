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
#include <errno.h>
#include <UdaUtil.h>
#include <IOUtility.h>
#include "UdaBridge.h"


////////////////////////////////////////////////////////////////////////////////
struct UdaThreadArgs{
	   const char * __caller_func;
	   void *(*__start_routine) (void *)  throw (UdaException*);
	   void *__arg;

	   UdaThreadArgs(const char * __caller_func, void *(*__start_routine) (void *), void *__arg) {
		   this -> __caller_func = __caller_func;
		   this -> __start_routine = __start_routine;
		   this -> __arg = __arg;
	   }
};

////////////////////////////////////////////////////////////////////////////////
void * udaThreadStart(void *arg) {
	UdaThreadArgs* threadArgs = (UdaThreadArgs*)arg;

	JNIEnv *jniEnv = NULL;
	void * ret = NULL;
	try {
		jniEnv = UdaBridge_attachNativeThread();
		log(lsINFO, "C++ THREAD STARTED (by %s) and attached to JVM tid=0x%x", threadArgs->__caller_func, (int)pthread_self());

		// HERE RUN the entire THREAD...
		ret = threadArgs->__start_routine(threadArgs->__arg);

		log(lsINFO, "C++ THREAD will be DETACHED and TERMINATED (started by %s) tid=0x%x", threadArgs->__caller_func, (int)pthread_self());

		delete threadArgs;
		UdaBridge_detachNativeThread();

		// no log after dettachNativeThread !!!

	}
	catch(UdaException *ex) {
		log(lsERROR, "got UdaException!");
		UdaBridge_exceptionInNativeThread(jniEnv, ex);
	}
    catch (std::exception *ex) {
    	log(lsERROR, "got exception : %s ", ex->what());
		UdaBridge_exceptionInNativeThread(jniEnv, NULL);
    }
	catch(...) {
		log(lsERROR, "got general Exception!");
		UdaBridge_exceptionInNativeThread(jniEnv, NULL);
	}

	return ret;
}

////////////////////////////////////////////////////////////////////////////////
/* wrapper for thread_create has same interface but does additional actions */
int uda_thread_create_func (
			   pthread_t * __newthread,
			   __const pthread_attr_t *__attr,
			   void *(*__start_routine) (void *),
//			   void *__arg, const char * callerFunc) __THROW {
			   void *__arg, const char * callerFunc) throw (UdaException*) {

	UdaThreadArgs *udaThreadArgs = new UdaThreadArgs(callerFunc, __start_routine, __arg);

	int ret = pthread_create(__newthread, __attr, udaThreadStart, udaThreadArgs);

	if (ret != 0) {
		errno = ret;
		log(lsERROR, "pthread_create failed error=%d (%m)!", errno);
		throw new UdaException("pthread_create failed");
	}
	return ret;
}

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
