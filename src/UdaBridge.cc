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

#include "UdaBridge.h"
#include "IOUtility.h"
#include "MOFServer/IndexInfo.h"
#include "MOFServer/MOFSupplierMain.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <UdaUtil.h>
#include "Merger/reducer.h"

//
// We cache all needed Java handles, for best performance of C++ -> Java calls.
//
// NOTE: All these handles are defined and calculated in a way that keeps
// them valid as long as the Java's UdaBridge class is loaded.
// => Hence, we are recalculating them in our JNI_OnLoad function
//
static JavaVM *cached_jvm;
static jweak  jweakUdaBridge; // use weak global ref for allowing GC to unload & re-load the class and handles
static jclass jclassUdaBridge; // just casted ref to above jweakUdaBridge. Hence, has same life time
static jmethodID jmethodID_fetchOverMessage; // handle to java cb method
static jmethodID jmethodID_dataFromUda; // handle to java cb method
static jmethodID jmethodID_getPathUda; // handle to java cb method
static jmethodID jmethodID_getConfData; // handle to java cb method
static jmethodID jmethodID_logToJava; // handle to java cb method
static jfieldID fidOffset;
static jfieldID fidRawLength;
static jfieldID fidPartLength;
static jfieldID fidPathMOF;


//forward declarion until in H file...
int MergeManager_main(int argc, char* argv[]) throw (UdaException*);

typedef void (*downcall_handler_t) (const std::string & msg);
typedef int (*main_t)(int argc, char* argv[]);
static downcall_handler_t my_downcall_handler;
static main_t my_main;
static bool is_net_merger;



typedef struct data_from_java
{
	uint64_t   offset;     /* Offset in the index file */
	uint64_t   rawLength;  /* decompressed length of MOF */
	uint64_t   partLength; /* compressed size of MOF partition */
	std::string path;
} data_from_java_t;

////////////////////////////////////////////////////////////////////////////////
// this does nothing
// serve as sanity in case C++ failed and Java remains up (fallback)
static void null_downcall_handler(const std::string & msg){

	//log(lsWARN, "got command after C++ termination"); //TODO: check if logger is safe and then open it!
}

////////////////////////////////////////////////////////////////////////////////
static void exceptionInJniThread(JNIEnv *env, UdaException *ex) {

	const char * info = ex ? ex->_info : "unexpected failure";
	const char * full_message = ex ? ex->getFullMessage().c_str() : "unexpected failure";

	my_downcall_handler = null_downcall_handler; // don't handle incoming commands any more

	if (is_net_merger) {

		const char *JNI_EXCEPTION_CLASS_NAME = "com/mellanox/hadoop/mapred/UdaRuntimeException";
		log(lsERROR, "raising %s to java side, with info=%s", JNI_EXCEPTION_CLASS_NAME, info);

		//Find the exception class.
		jclass exClass = env->FindClass(JNI_EXCEPTION_CLASS_NAME);
		if (exClass == NULL) {
			log(lsERROR, "Not found %s",JNI_EXCEPTION_CLASS_NAME);
			return;
		}
		//Indicate the exception with error message to JNI - NOTE: exception will occur after C++ terminates
		env->ThrowNew(exClass, full_message);
		env->DeleteLocalRef(exClass);
	}
	else {
		log(lsERROR, "unexpected error info=%s, full-message=%s", info, full_message);
		// TODO ...
	}
}

//direct buffer requires java 1.4
extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *jvm, void *reserved)
{
	errno = 0; // we don't want the value from JVM
	printf("-->> In C++ JNI_OnLoad\n");

	cached_jvm = jvm;
	JNIEnv *env;
	if ( jvm->GetEnv((void **)&env, JNI_VERSION_1_4)) { //direct buffer requires java 1.4
		return JNI_ERR; /* JNI version not supported */
	}

	jclass cls = env->FindClass("com/mellanox/hadoop/mapred/UdaBridge");
	if (cls == NULL) {
		printf("-->> In C++ java class was NOT found\n");
		return JNI_ERR;
	}

	// keeps the handle valid after function exits, but still, use weak global ref
	// for allowing GC to unload & re-load the class and handles
	jweakUdaBridge = env->NewWeakGlobalRef(cls);
	if (jweakUdaBridge == NULL) {
		printf("-->> In C++ weak global ref to java class was NOT found\n");
		return JNI_ERR;
	}
	jclassUdaBridge = (jclass) jweakUdaBridge;

	// This handle remains valid until the java class is Unloaded
	//fetchOverMessage callback
	jmethodID_fetchOverMessage = env->GetStaticMethodID(jclassUdaBridge, "fetchOverMessage", "()V");
	if (jmethodID_fetchOverMessage == NULL) {
		printf("-->> In C++ java UdaBridge.fetchOverMessage() callback method was NOT found\n");
		return JNI_ERR;
	}

	//dataFromUda callback
	jmethodID_dataFromUda = env->GetStaticMethodID(cls, "dataFromUda", "(Ljava/lang/Object;I)V");
	if (jmethodID_dataFromUda == NULL) {
		printf("-->> In C++ java UdaBridge.jmethodID_dataFromUda() callback method was NOT found\n");
		return JNI_ERR;
	}

	//dataFromUda callback
	jmethodID_getPathUda = env->GetStaticMethodID(jclassUdaBridge, "getPathUda", "(Ljava/lang/String;Ljava/lang/String;I)Ljava/lang/Object;");
	if (jmethodID_getPathUda == NULL) {
		printf("-->> In C++ java UdaBridge.jmethodID_getPathUda() callback method was NOT found\n");
		return JNI_ERR;
	}

	//getConfData callback
	jmethodID_getConfData = env->GetStaticMethodID(jclassUdaBridge, "getConfData", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
	if (jmethodID_getConfData == NULL) {
		printf("-->> In C++ java UdaBridge.jmethodID_getConfData() callback method was NOT found\n");
		return JNI_ERR;
	}

	//logToJava callback
	jmethodID_logToJava = env->GetStaticMethodID(jclassUdaBridge, "logToJava", "(Ljava/lang/String;I)V");
	if (jmethodID_logToJava == NULL) {
		printf("-->> In C++ java UdaBridge.logToJava() callback method was NOT found\n");
		return JNI_ERR;
	}

	printf("-->> In C++ java callback methods were found and cached\n");
	return JNI_VERSION_1_4;  //direct buffer requires java 1.4
}

extern "C" JNIEXPORT void JNICALL JNI_OnUnload(JavaVM *jvm, void *reserved)
{
	errno = 0; // we don't want the value from JVM
	// NOTE: We never reached this place
	printf("-->> In C++ JNI_OnUnload\n");

	JNIEnv *env;
	if (jvm->GetEnv((void **)&env, JNI_VERSION_1_4)) {
		return;
	}
	env->DeleteWeakGlobalRef(jweakUdaBridge);
	return;
}


// This is the implementation of the native method
extern "C" JNIEXPORT jint JNICALL Java_com_mellanox_hadoop_mapred_UdaBridge_startNative  (JNIEnv *env, jclass cls, jboolean isNetMerger, jobjectArray stringArray, jint log_level, jboolean log_to_uda_file) {
	int ret = 0;
	try{
		errno = 0; // we don't want the value from JVM

		//set the global log's threshold
		log_set_threshold((log_severity_t)log_level);

		log_set_logging_mode(log_to_uda_file);

		printf("-->> In C++ Java_com_mellanox_hadoop_mapred_UdaBridge_startNative\n");

		int argc = env->GetArrayLength(stringArray);
		char **argv = new char*[argc];

		printf("-- argc=%d\n", argc);

		for (int i=0; i<argc; i++) {
			//printf("-- i=%d\n", i);
			jstring string = (jstring) env->GetObjectArrayElement(stringArray, i);
			if (string != NULL) {
				const char *rawString = env->GetStringUTFChars(string, 0);
				argv[i] = strdup(rawString);
				env->ReleaseStringUTFChars(string, rawString);
			}
			else {
				argv[i] = strdup("");
			}
		}

		is_net_merger = isNetMerger;
		if (is_net_merger) {
			printf("In NetMerger 'C++ main from Java Thread'\n");
			my_downcall_handler = reduce_downcall_handler;
			my_main = MergeManager_main;
		}
		else {
			printf("In MOFSupplier 'C++ main from Java Thread'\n");
			my_downcall_handler = mof_downcall_handler;
			my_main = MOFSupplier_main;
		}

		ret = my_main(argc, argv);
		if (ret != 0) {
			log(lsERROR, "error in main");
			throw new UdaException("error in main");
		}

		log(lsINFO, "main initialization finished ret=%d", ret);
		if (! is_net_merger) {
			pthread_t thr;
			uda_thread_create(&thr, NULL, MOFSupplierRun, NULL);  // This is actual main of MOFSupplier
		}

		for (int i=0; i < argc; i++) {
			free (argv[i]);
		}
		delete [] argv;

		log(lsTRACE, "<<< finished");
		printf("<<-- Finished C++ Java_com_mellanox_hadoop_mapred_UdaBridge_startNative\n");

	}
	catch (UdaException *ex) {
		exceptionInJniThread(env, ex);
	}
    catch (exception *ex) {
		log(lsERROR, "got STL exception: %s", ex->what());
		exceptionInJniThread(env, NULL);
    }
    catch(...) {
		log(lsERROR, "got general Exception!");
		exceptionInJniThread(env, NULL);
    }

    return ret;
}

// This is the implementation of the native method
extern "C" JNIEXPORT void JNICALL Java_com_mellanox_hadoop_mapred_UdaBridge_doCommandNative  (JNIEnv *env, jclass cls, jstring s) {
	try {
		errno = 0; // we don't want the value from JVM
		log(lsTRACE, ">>> started");

		const char *str = env->GetStringUTFChars(s, NULL);
		if (str == NULL) {
			log(lsERROR, "out of memory in JNI call to GetStringUTFChars");
			throw new UdaException("Out of Memory");
		}
		std::string msg(str);
		env->ReleaseStringUTFChars(s, str);


		my_downcall_handler(msg);

		log(lsTRACE, "<<< finished");
	}
	catch (UdaException *ex) {
		exceptionInJniThread(env, ex);
	}
    catch (exception *ex) {
		log(lsERROR, "got STL exception: %s", ex->what());
		exceptionInJniThread(env, NULL);
    }
    catch(...) {
		log(lsERROR, "got general Exception!");
		exceptionInJniThread(env, NULL);
    }
}


// This is the implementation of the native method
extern "C" JNIEXPORT void JNICALL Java_com_mellanox_hadoop_mapred_UdaBridge_setLogLevelNative  (jclass cls, jint log_level) {
	try {
		log_set_threshold((log_severity_t)log_level);
	}
	// Exception in this method will not cause a fallback,
	// so WE DO NOT call exceptionInJniThread(env, ex) here.
    catch (UdaException *ex) {
    	log(lsWARN, "failed to set log level: info=%s, full-message=%s ", ex->_info, ex->getFullMessage().c_str());
    }
    catch (exception *ex) {
    	log(lsWARN, "failed to set log level: Exception : %s ", ex->what());
    }
    catch (...) {
    	log(lsWARN, "failed to set log level : unexpected error");
    }
}


// must be called with JNIEnv that matched the caller's thread - see attachNativeThread() above
// - otherwise TOO BAD unexpected results are expected!
void UdaBridge_invoke_fetchOverMessage_callback(JNIEnv * jniEnv) {
	log(lsTRACE, "before jniEnv->CallStaticVoidMethod...");
	jniEnv->CallStaticVoidMethod(jclassUdaBridge, jmethodID_fetchOverMessage);
	log(lsTRACE, "after  jniEnv->CallStaticVoidMethod...");
}

// must be called with JNIEnv that matched the caller's thread - see attachNativeThread() above
// - otherwise TOO BAD unexpected results are expected!
void UdaBridge_invoke_dataFromUda_callback(JNIEnv * jniEnv, jobject jbuf, int len) {
	log(lsTRACE, "before jniEnv->CallStaticVoidMethod jniEnv=%p, jbuf=%p, len=%d", jniEnv, jbuf, len);
	jniEnv->CallStaticVoidMethod(jclassUdaBridge, jmethodID_dataFromUda, jbuf, len);
	log(lsTRACE, "after  jniEnv->CallStaticVoidMethod...");
}

index_record* UdaBridge_invoke_getPathUda_callback(JNIEnv * jniEnv, const char* job_id, const char* map_id, int reduceId) {
	jstring jstr_job, jstr_map;
	jstr_job = jniEnv->NewStringUTF(job_id);
	jstr_map = jniEnv->NewStringUTF(map_id); //NewStringUTF allocates a string inside the JVM which will release it
	log(lsTRACE, "before jniEnv->CallStaticObjectMethod...");

	jobject jdata = jniEnv->CallStaticObjectMethod(jclassUdaBridge, jmethodID_getPathUda, jstr_job,  jstr_map, reduceId);
	log(lsTRACE, "after  jniEnv->CallStaticObjectMethod...");

	jniEnv->DeleteLocalRef(jstr_job);
	jniEnv->DeleteLocalRef(jstr_map);

	if (jdata==NULL){
		log(lsERROR, "java_UdaBridge.getPathUda returned null! for job_id=%s, map_id=%s, reduceId=%d", job_id, map_id, reduceId);
		return NULL;
	}
	
	static jclass cls_data = jniEnv->GetObjectClass(jdata);

	if (fidOffset == NULL) {
		fidOffset = jniEnv->GetFieldID(cls_data, "startOffset", "J");
		 if (fidOffset == NULL) {
			 log(lsERROR, "java_UdaBridge.GetFieldID() callback method for startOffset was NOT found");
			 return NULL;
		 }
	 }

	if (fidRawLength == NULL) {
		fidRawLength = jniEnv->GetFieldID(cls_data, "rawLength", "J");
		 if (fidRawLength == NULL) {
			 log(lsERROR, "java_UdaBridge.GetFieldID() callback method for rawLength was NOT found");
			 return NULL;
		 }
	 }


	if (fidPartLength == NULL) {
		fidPartLength = jniEnv->GetFieldID(cls_data, "partLength", "J");
		 if (fidPartLength == NULL) {
			 log(lsERROR, "java_UdaBridge.GetFieldID() callback method for partLength was NOT found");
			 return NULL;
		 }
	 }

	if (fidPathMOF == NULL) {
		fidPathMOF = jniEnv->GetFieldID(cls_data, "pathMOF", "Ljava/lang/String;");
		 if (fidPathMOF == NULL) {
			 log(lsERROR, "java_UdaBridge.GetFieldID() callback method for pathMOF was NOT found");
			 return NULL;
		 }
	 }

	index_record *data = (index_record*) malloc(sizeof(index_record));
	data->offset = (int64_t) jniEnv->GetLongField(jdata, fidOffset);
	data->rawLength = (int64_t) jniEnv->GetLongField(jdata, fidRawLength);
	data->partLength = (int64_t) jniEnv->GetLongField(jdata, fidPartLength);
	data->path = (jstring)jniEnv->GetObjectField(jdata, fidPathMOF);

	log(lsDEBUG, "after  jniEnv->CallStaticVoidMethod... ");
	return data;
}



std::string UdaBridge_invoke_getConfData_callback(const char* paramName, const char* defaultValue) {
	JNIEnv *env = UdaBridge_threadGetEnv();
	if (!env) {
		return NULL;
	}
	jstring jstr_param = env->NewStringUTF(paramName);
	jstring jstr_default = env->NewStringUTF(defaultValue);
	jobject jdata = env->CallStaticObjectMethod(jclassUdaBridge, jmethodID_getConfData, jstr_param,jstr_default);
	env->DeleteLocalRef(jstr_param);
	env->DeleteLocalRef(jstr_default);
	if (jdata==NULL){
		log(lsERROR, "java UdaBridge.getConfData returned null!");
		return NULL;
	}
	const char *nativeString = env->GetStringUTFChars( (jstring) jdata, 0);
	std::string value(nativeString); // !!!
	env->ReleaseStringUTFChars( (jstring)jdata, nativeString);
	log(lsDEBUG, "UdaBridge_invoke_getConfData_callback: paramName=%s, defaultValue=%s, retValue=%s", paramName, defaultValue, nativeString);
	return value;
}


void UdaBridge_invoke_logToJava_callback(const char* log_message, int severity) {
	JNIEnv *env;
	if (cached_jvm->GetEnv((void **)&env, JNI_VERSION_1_4)) {
		printf("-->> Error getting JNIEnv In C++ JNI_logToJava when trying to log message - %s\n", log_message);
		return;
	}

	jstring j_message = env->NewStringUTF(log_message);
	env->CallStaticVoidMethod(jclassUdaBridge, jmethodID_logToJava, j_message, severity);
	env->DeleteLocalRef(j_message);

}


// a utility function that attaches the **current [native] thread** to the JVM and
// return the JNIEnv interface pointer for this thread
// BE CAREFUL:
// - DON'T use the handle from one thread in context of another threads!
JNIEnv *UdaBridge_attachNativeThread()
{
	// DO NOT log before cached_jvm->AttachCurrentThread
    JNIEnv *env;
	if (! cached_jvm) {
		log(lsERROR, "cached_jvm is NULL");
		throw new UdaException("cached_jvm is NULL");
	}
    jint ret = cached_jvm->AttachCurrentThread((void **)&env, NULL);

	if (ret < 0) {
		log(lsERROR, "cached_jvm->AttachCurrentThread failed ret=%d", ret);
		throw new UdaException("cached_jvm->AttachCurrentThread failed");
	}
	log(lsTRACE, "completed successfully env=%p", env);
    return env; // note: this handler is valid for all functions in this tread
}

JNIEnv *UdaBridge_threadGetEnv()
{
	JNIEnv *jniEnv;
	if (cached_jvm->GetEnv((void **)&jniEnv, JNI_VERSION_1_4)) {
		throw new UdaException("GetEnv failed");
	}
	return jniEnv;
}


////////////////////////////////////////////////////////////////////////////////
void UdaBridge_exceptionInNativeThread(JNIEnv *env, UdaException *ex) {

	std::string msg = ex ? ex->getFullMessage() : string ("unexpected error");
	log(lsERROR, "UDA has encountered a critical error and will try to fallback to vanilla MSG=%s", msg.c_str());

	my_downcall_handler = null_downcall_handler; // don't handle incoming commands any more

	if (is_net_merger) {

		// This handle remains valid until the java class is Unloaded
		jmethodID jmethodID_failureInUda = env->GetStaticMethodID(jclassUdaBridge, "failureInUda", "()V");
		if (jmethodID_failureInUda == NULL) {
			log(lsERROR, "UdaBridge.failureInUda() callback method was NOT found");
			return;
		}

		env->CallStaticVoidMethod(jclassUdaBridge, jmethodID_failureInUda);


	}
	else {
		//TODO: complete....
	}

}


// must be called with JNIEnv that matched the caller thread - see attachNativeThread() above
// - otherwise TOO BAD unexpected results are expected!
jobject UdaBridge_registerDirectByteBuffer(JNIEnv * jniEnv,  void* address, long capacity) {

	log(lsDEBUG, "registering native buffer for JAVA usage (address=%p, capacity=%ld) ...", address, capacity);
	jobject jbuf = jniEnv->NewDirectByteBuffer(address, capacity);

	if (jbuf) {
		jbuf = (jobject) jniEnv->NewWeakGlobalRef(jbuf); // Don't let GC to reclaim it while we need it
		if (!jbuf){
			log(lsERROR, "failed NewWeakGlobalRef");
		}
	}
	else {
		log(lsERROR, "failed NewDirectByteBuffer");
	}

	return jbuf;
}




