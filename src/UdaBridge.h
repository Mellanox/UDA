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

#ifndef UdaBridge__H___
#define UdaBridge__H___

#include <jni.h>


//forward declarations

struct index_record;
class UdaException;

// wrappers arround java callbck methods
void          UdaBridge_invoke_fetchOverMessage_callback(JNIEnv * jniEnv);
void          UdaBridge_invoke_dataFromUda_callback(JNIEnv * jniEnv, jobject jbuf, int len);
void          UdaBridge_invoke_logToJava_callback(const char* log_message, int severity);
index_record* UdaBridge_invoke_getPathUda_callback (JNIEnv * jniEnv, const char* job_id, const char* map_id, int reduceId);


// UdaBridge utility functions
JNIEnv *UdaBridge_attachNativeThread();
JNIEnv *UdaBridge_threadGetEnv();
void    UdaBridge_exceptionInNativeThread(JNIEnv *env, UdaException *ex);
jobject UdaBridge_registerDirectByteBuffer(JNIEnv * jniEnv,  void* address, long capacity);

#endif // ! UdaBridge__H___
