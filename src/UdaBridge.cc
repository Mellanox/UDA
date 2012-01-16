
#include "UdaBridge.h"
#include "IOUtility.h"

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


//forward declarion until in H file...
void reduce_downcall_handler(const std::string & msg); // #include "reducer.h"
int MergeManager_main(int argc, char* argv[]);
int MOFSupplier_main(int argc, char* argv[]);

//void mof_downcall_handler(progress_event_t *pevent, void *ctx);

typedef void (*downcall_handler_t) (const std::string & msg);
typedef int (*main_t)(int argc, char* argv[]);
static downcall_handler_t my_downcall_handler;
static main_t my_main;
static bool is_net_merger;


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

	jclass cls = env->FindClass("org/apache/hadoop/mapred/UdaBridge");
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
	int    argc;
	char** argv;
	Args(int _argc, char** _argv) : argc(_argc), argv(_argv){}
};

void* mainThread(void* data)
{
	Args* pArgs = (Args*) data;
    printf("In C++ main thread: calling: MOFSupplier_main\n");

    for (int i=0; i<pArgs->argc; i++) {
        printf ("%d: %s\n", i, pArgs->argv[i]);
    }

    // change only this line (based on argv[0]) if you want to start MOFSupplier
    int rc = MOFSupplier_main(pArgs->argc, pArgs->argv);

    printf("In C++ main thread: MOFSupplier_main returned %d\n", rc);

    for (int i=0; i<pArgs->argc; i++) {
        free (pArgs->argv[i]);
    }
    delete[] pArgs->argv;
    delete pArgs;
}


// This is the implementation of the native method
extern "C" JNIEXPORT void JNICALL Java_org_apache_hadoop_mapred_UdaBridge_doCommandNative  (JNIEnv *env, jclass cls, jstring s) {
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

// a utility function that attaches the **current native thread** to the JVM and
// return the JNIEnv interface pointer for this thread
// BE CAREFUL:
// - DON'T call this function more than once for the same thread!!
// - DON'T use the handle from one thread in context of another threads!
extern "C" JNIEnv *attachNativeThread()
{
	log(lsTRACE, "attachNativeThread started");
    JNIEnv *env;
	if (! cached_jvm) {
		log(lsFATAL, "cached_jvm is NULL");
		exit (1);
	}
	log(lsDEBUG, "attachNativeThread before AttachCurrentThread(..)");
    jint ret = cached_jvm->AttachCurrentThread((void **)&env, NULL);

	if (ret < 0) {
		log(lsFATAL, "cached_jvm->AttachCurrentThread failed ret=%d", ret);
		exit (1);
	}
	log(lsINFO, "attachNativeThread completed successfully env=%p", env);
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

// must be called with JNIEnv that matched the caller thread - see attachNativeThread() above
// - otherwise TOO BAD unexpected results are expected!
extern "C" jobject UdaBridge_registerDirectByteBuffer(JNIEnv * jniEnv,  void* address, long capacity) {

	log(lsINFO, "registering native buffer for JAVA usage (address=%p, capacity=%ld) ...", address, capacity);
	jobject jbuf = jniEnv->NewDirectByteBuffer(address, capacity);

	void* _address = jniEnv->GetDirectBufferAddress(jbuf);
	jlong _capacity = jniEnv->GetDirectBufferCapacity(jbuf);
	if (jbuf) {
		if (_address != address)
		{
			log(lsFATAL, "invalid buffer address: expected %p but was %p", address, _address);
			jbuf = NULL;
		}
		if (_capacity != capacity)
		{
			log(lsFATAL, "invalid buffer capacity: expected %d but was %d", capacity, _capacity);
			jbuf = NULL;
		}
	}
	else
	{
		// access to direct buffers not supported
		if (_address != NULL | _capacity != -1)
		{
			log(lsFATAL, "inconsistent NIO support: "
					"NewDirectByteBuffer() returned NULL; "
					"GetDirectBufferAddress() returned %p; "
					"GetDirectBufferCapacity() returned %d", _address, _capacity);
		}
		else
		{
			log(lsFATAL, "no NIO support");
		}
	}

	if (jbuf) {
		// Don't let GC to reclaim it while we need it
	    jweak weakBuf = jniEnv->NewWeakGlobalRef(jbuf);
	    if (weakBuf == NULL) {
			log(lsFATAL, "failed NewWeakGlobalRef");
	    }
	    jbuf = (jobject)weakBuf;

	}
	return jbuf;
}

// This is the implementation of the native method
extern "C" JNIEXPORT jint JNICALL Java_org_apache_hadoop_mapred_UdaBridge_startNative  (JNIEnv *env, jclass cls, jobjectArray stringArray, jboolean isNetMerger) {

	errno = 0; // we don't want the value from JVM
	log(lsTRACE, ">>> started");

	int argc = env->GetArrayLength(stringArray);
    char **argv = new char*[argc];

    for (int i=0; i<argc; i++) {
        jstring string = (jstring) env->GetObjectArrayElement(stringArray, i);
        const char *rawString = env->GetStringUTFChars(string, 0);
        argv[i] = strdup(rawString);
        env->ReleaseStringUTFChars(string, rawString);
    }

    is_net_merger = isNetMerger;
    if (is_net_merger) {
        printf("In NetMerger 'C++ main from Java Thread'\n");
    	my_downcall_handler = reduce_downcall_handler;
    	my_main = MergeManager_main;
    }
    else {

        printf("In MOFSupplier 'C++ main from Java Thread'\n");
        Args *pArgs = new Args(argc, argv);

        pthread_t thr;
        pthread_create(&thr, NULL, mainThread, pArgs);
        sleep(5);//temp
        printf("exiting 'C++ from Java Thread'\n");

        return (0);

    }

    int ret = my_main(argc, argv);
	log(lsINFO, "main finished ret=%d", ret);
	for (int i=0; i < argc; i++) {
        free (argv[i]);
    }
	delete [] argv;

	log(lsTRACE, "<<< finished");
    return ret;
}


