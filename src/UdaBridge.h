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

#ifdef __cplusplus
extern "C" {
#endif


//forward declarations

struct index_record;

jobject UdaBridge_registerDirectByteBuffer(JNIEnv * jniEnv,  void* address, long capacity);
void UdaBridge_invoke_fetchOverMessage_callback(JNIEnv * jniEnv);
void UdaBridge_invoke_dataFromUda_callback(JNIEnv * jniEnv, jobject jbuf, int len);
index_record* UdaBridge_invoke_getPathUda_callback (JNIEnv * jniEnv, const char* job_id, const char* map_id, int reduceId);

// a utility function that attach the **current native thread** to the JVM and
// return the JNIEnv interface pointer for this thread
// BE CAREFUL:
// - DON'T call this function more than once for the same thread!! - perhaps not critical!
// - DON'T use the handle from one thread in context of another thread!

JNIEnv *attachNativeThread();


#ifdef __cplusplus
}
#endif


#endif // ! UdaBridge__H___
