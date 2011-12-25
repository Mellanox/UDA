
#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h> //temp for sleep

#include "IOUtility.h"

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

//forward declarion until in H file...
void downcall_handler(const std::string & msg); // #include "reducer.h"
int MergeManager_main(int argc, char* argv[]);


//direct buffer requires java 1.4
extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *jvm, void *reserved)
{
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
    jmethodID_fetchOverMessage = env->GetStaticMethodID(jclassUdaBridge, "fetchOverMessage", "()V");

	if (jmethodID_fetchOverMessage == NULL) {
		printf("-->> In C++ java UdaBridge.fetchOverMessage() callback method was NOT found\n");
        return JNI_ERR;
    }

	printf("-->> In C++ java callback method were found and cached\n");
	return JNI_VERSION_1_4;  //direct buffer requires java 1.4
}

extern "C" JNIEXPORT void JNICALL JNI_OnUnload(JavaVM *jvm, void *reserved)
{
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
    printf("In C++ main thread: calling: MergeManager_main\n");

    for (int i=0; i<pArgs->argc; i++) {
        printf ("%d: %s\n", i, pArgs->argv[i]);
    }

    // change only this line (based on argv[0]) if you want to start MOFSupplier
    int rc = MergeManager_main(pArgs->argc, pArgs->argv);

    printf("In C++ main thread: MergeManager_main returned %d\n", rc);

    for (int i=0; i<pArgs->argc; i++) {
        free (pArgs->argv[i]);
    }
    delete[] pArgs->argv;
    delete pArgs;
}


// This is the implementation of the native method
extern "C" JNIEXPORT void JNICALL Java_org_apache_hadoop_mapred_UdaBridge_doCommand  (JNIEnv *env, jclass cls, jstring s) {

	const char *str = env->GetStringUTFChars(s, NULL);
	if (str == NULL) {
		log(lsFATAL, "out of memory in JNI call to GetStringUTFChars");
		throw "Out of Memory";
	}
	std::string msg(str);
	env->ReleaseStringUTFChars(s, str);

	downcall_handler(msg);
}

// a utility function that attach the **current native thread** to the JVM and
// return the JNIEnv interface pointer for this thread
// BE CAREFUL:
// - DON'T call this function more than once for a thread!!
// - DON'T use the handle from one thread in context of another threads!
JNIEnv *attachNativeThread()
{
	log(lsTRACE, "attachNativeThread started");
    JNIEnv *env;
	if (! cached_jvm) {
		log(lsFATAL, "cached_jvm is NULL");
		printf("-->> In C++ attachNativeThread: ERROR: cached_jvm is NULL\n");
		exit (1);
	}
	log(lsDEBUG, "attachNativeThread before AttachCurrentThread(..)");
    jint ret = cached_jvm->AttachCurrentThread((void **)&env, NULL);

	if (ret < 0) {
		log(lsFATAL, "cached_jvm->AttachCurrentThread failed ret=%d", ret);
		printf("-->> In C++ attachNativeThread: ERROR: cached_jvm->AttachCurrentThread failed ret=%d\n", ret);
		exit (1);
	}
	log(lsTRACE, "attachNativeThread completed successfully env=%p", env);
    return env; // note: this handler is valid for all functions in this tread
}

// must be called from same thread at all times - otherwise TOO BAD unexpected results are expected!
void UdaBridge_invoke_fetchOverMessage_callback() {
	static JNIEnv * jniEnv = attachNativeThread();

	log(lsTRACE, "before jniEnv->CallStaticVoidMethod...");
	jniEnv->CallStaticVoidMethod(jclassUdaBridge, jmethodID_fetchOverMessage);
	log(lsTRACE, "after  jniEnv->CallStaticVoidMethod...");
}

// This is the implementation of the native method
extern "C" JNIEXPORT jint JNICALL Java_org_apache_hadoop_mapred_UdaBridge_start  (JNIEnv *env, jclass cls, jobjectArray stringArray) {

    int argc = env->GetArrayLength(stringArray);
    char **argv = new char*[argc];

    for (int i=0; i<argc; i++) {
        jstring string = (jstring) env->GetObjectArrayElement(stringArray, i);
        const char *rawString = env->GetStringUTFChars(string, 0);
        argv[i] = strdup(rawString);
        env->ReleaseStringUTFChars(string, rawString);
    }

    printf("In 'C++ from Java Thread'\n");

    Args *pArgs = new Args(argc, argv);

    pthread_t thr;
    pthread_create(&thr, NULL, mainThread, pArgs);
    sleep(10);//temp
    printf("exiting 'C++ from Java Thread'\n");
    return 0;
}


