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

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h> //temp for sleep


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
static jfieldID fidOffset;
static jfieldID fidRawLength;
static jfieldID fidPartLength;
static jfieldID fidPathMOF;


//forward declarion until in H file...
const char * reduce_downcall_handler(const std::string & msg); // #include "reducer.h"
int MergeManager_main(int argc, char* argv[]);

const char * mof_downcall_handler(const std::string & msg); // #include ...
int MOFSupplier_main(int argc, char* argv[]);
extern "C" void * MOFSupplierRun(void *);

typedef const char * (*downcall_handler_t) (const std::string & msg);
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



void indicateUdaJniException(JNIEnv *env, UdaException *ex) {

	const char *JNI_EXCEPTION_CLASS_NAME = "java/lang/RuntimeException"; //TODO: create our own class
	//	log_func(func, file, line, lsERROR, "raising %s to java side, with info=%s", JNI_EXCEPTION_CLASS_NAME, info);
	log(lsERROR, "raising %s to java side, with info=%s", JNI_EXCEPTION_CLASS_NAME, ex->_info);


	//Find the exception class.
	jclass exClass = env->FindClass(JNI_EXCEPTION_CLASS_NAME);
	if (exClass == NULL) {
		log(lsERROR, "Not found %s",JNI_EXCEPTION_CLASS_NAME);
		return;
	}
	//Indicate the exception with error message to JNI - NOTE: exception will occur after C++ terminates
	env->ThrowNew(exClass, ex->getFullMessage().c_str());
	env->DeleteLocalRef(exClass);
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



struct Args{
	main_t mainf;
	int    argc;
	char** argv;
	Args(main_t _mainf, int _argc, char** _argv) : mainf(_mainf), argc(_argc), argv(_argv){}
};

void* mainThread(void* data)
{
	Args* pArgs = (Args*) data;

	printf("In C++ main thread: calling: main\n");
    int rc = pArgs->mainf(pArgs->argc, pArgs->argv);

    printf("In C++ main thread: main returned %d\n", rc);
    for (int i=0; i<pArgs->argc; i++) {
        free (pArgs->argv[i]);
    }
    delete[] pArgs->argv;
    delete pArgs;

    return NULL;
}


// This is the implementation of the native method
extern "C" JNIEXPORT jint JNICALL Java_com_mellanox_hadoop_mapred_UdaBridge_startNative  (JNIEnv *env, jclass cls, jboolean isNetMerger, jobjectArray stringArray) {
	int ret = 0;
	try{
		errno = 0; // we don't want the value from JVM
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
			fprintf(stdout, "error in main'\n");
			fprintf(stderr, "error in main'\n");
			log(lsFATAL, "error in main");
			exit(255); //TODO: this is too brutal
		}

		log(lsINFO, "main initialization finished ret=%d", ret);
		if (! is_net_merger) {
			pthread_t thr;
			log(lsINFO, "CREATING THREAD"); pthread_create(&thr, NULL, MOFSupplierRun, NULL);  // This is actual main of MOFSupplier
		}

		for (int i=0; i < argc; i++) {
			free (argv[i]);
		}
		delete [] argv;

		log(lsTRACE, "<<< finished");
		printf("<<-- Finished C++ Java_com_mellanox_hadoop_mapred_UdaBridge_startNative\n");

	}
	catch (UdaException *ex) {
		indicateUdaJniException(env, ex);
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
			log(lsFATAL, "out of memory in JNI call to GetStringUTFChars");
			throw "Out of Memory";
		}
		std::string msg(str);
		env->ReleaseStringUTFChars(s, str);


		my_downcall_handler(msg);

		log(lsTRACE, "<<< finished");
	}
	catch (UdaException *ex) {
		indicateUdaJniException(env, ex);
	}
}

// a utility function that attaches the **current [native] thread** to the JVM and
// return the JNIEnv interface pointer for this thread
// BE CAREFUL:
// - DON'T call this function more than once for the same thread!! - perhaps not critical!
// - DON'T use the handle from one thread in context of another threads!
extern "C" JNIEnv *attachNativeThread()
{
	log(lsTRACE, "started");
    JNIEnv *env;
	if (! cached_jvm) {
		log(lsFATAL, "cached_jvm is NULL");
		exit (1);
	}
    jint ret = cached_jvm->AttachCurrentThread((void **)&env, NULL);

	if (ret < 0) {
		log(lsFATAL, "cached_jvm->AttachCurrentThread failed ret=%d", ret);
		exit (1);
	}
	log(lsTRACE, "completed successfully env=%p", env);
    return env; // note: this handler is valid for all functions in this tread
}

// must be called with JNIEnv that matched the caller's thread - see attachNativeThread() above
// - otherwise TOO BAD unexpected results are expected!
extern "C" void UdaBridge_invoke_fetchOverMessage_callback(JNIEnv * jniEnv) {
	log(lsTRACE, "before jniEnv->CallStaticVoidMethod...");
	jniEnv->CallStaticVoidMethod(jclassUdaBridge, jmethodID_fetchOverMessage);
	log(lsTRACE, "after  jniEnv->CallStaticVoidMethod...");
}

// must be called with JNIEnv that matched the caller's thread - see attachNativeThread() above
// - otherwise TOO BAD unexpected results are expected!
extern "C" void UdaBridge_invoke_dataFromUda_callback(JNIEnv * jniEnv, jobject jbuf, int len) {
	log(lsTRACE, "before jniEnv->CallStaticVoidMethod jniEnv=%p, jbuf=%p, len=%d", jniEnv, jbuf, len);
	jniEnv->CallStaticVoidMethod(jclassUdaBridge, jmethodID_dataFromUda, jbuf, len);
	log(lsTRACE, "after  jniEnv->CallStaticVoidMethod...");
}

extern "C" index_record* UdaBridge_invoke_getPathUda_callback(JNIEnv * jniEnv, const char* job_id, const char* map_id, int reduceId) {
	log(lsTRACE, "before jniEnv->CallStaticVoidMethod...");
	jstring jstr_job, jstr_map;
	jstr_job = jniEnv->NewStringUTF(job_id);
	jstr_map = jniEnv->NewStringUTF(map_id); //NewStringUTF allocates a string inside the JVM which will release it

	jobject jdata = jniEnv->CallStaticObjectMethod(jclassUdaBridge, jmethodID_getPathUda, jstr_job,  jstr_map, reduceId);
	log(lsTRACE, "after  jniEnv->CallStaticVoidMethod...");

	jniEnv->DeleteLocalRef(jstr_job);
	jniEnv->DeleteLocalRef(jstr_map);

	if (jdata==NULL){
		log(lsERROR, "-->> In C++ java UdaBridge.getPathUda returned null!");
		return NULL;
	}
	
	jclass cls_data = jniEnv->GetObjectClass(jdata);

	if (fidOffset == NULL) {
		fidOffset = jniEnv->GetFieldID(cls_data, "startOffset", "J");
		 if (fidOffset == NULL) {
			 log(lsERROR, "-->> In C++ java UdaBridge.GetFieldID() callback method for startOffset was NOT found");
			 return NULL;
		 }
	 }

	if (fidRawLength == NULL) {
		fidRawLength = jniEnv->GetFieldID(cls_data, "rawLength", "J");
		 if (fidRawLength == NULL) {
			 log(lsERROR, "-->> In C++ java UdaBridge.GetFieldID() callback method for rawLength was NOT found");
			 return NULL;
		 }
	 }


	if (fidPartLength == NULL) {
		fidPartLength = jniEnv->GetFieldID(cls_data, "partLength", "J");
		 if (fidPartLength == NULL) {
			 log(lsERROR, "-->> In C++ java UdaBridge.GetFieldID() callback method for partLength was NOT found");
			 return NULL;
		 }
	 }

	if (fidPathMOF == NULL) {
		fidPathMOF = jniEnv->GetFieldID(cls_data, "pathMOF", "Ljava/lang/String;");
		 if (fidPathMOF == NULL) {
			 log(lsERROR, "-->> In C++ java UdaBridge.GetFieldID() callback method for pathMOF was NOT found");
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

// must be called with JNIEnv that matched the caller thread - see attachNativeThread() above
// - otherwise TOO BAD unexpected results are expected!
extern "C" jobject UdaBridge_registerDirectByteBuffer(JNIEnv * jniEnv,  void* address, long capacity) {

	log(lsINFO, "registering native buffer for JAVA usage (address=%p, capacity=%ld) ...", address, capacity);
	jobject jbuf = jniEnv->NewDirectByteBuffer(address, capacity);

	if (jbuf) {
		jbuf = (jobject) jniEnv->NewWeakGlobalRef(jbuf); // Don't let GC to reclaim it while we need it
		if (!jbuf)
			log(lsERROR, "failed NewWeakGlobalRef");
	}
	else {
		log(lsERROR, "failed NewDirectByteBuffer");
	}

	return jbuf;
}


