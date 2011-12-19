#include <jni.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "org_apache_hadoop_mapred_JniTest.h"  

JavaVM *cached_jvm;
jmethodID MID_JniTest_callback;
jmethodID MID_JniTest_staticCallback;
//jclass javaClass;
jweak javaClass;

// a utility function that allows the native code to obtain the JNIEnv interface pointer 
// for the **current thread** - Don't use this handle from other threads!
JNIEnv *getJniEnv()
{
    JNIEnv *env;
	if (! cached_jvm) {
		printf("-->> In C++ getJniEnv: ERROR: cached_jvm is NULL\n");
		exit (1);
	}
    jint ret = cached_jvm->GetEnv((void **)&env, JNI_VERSION_1_4);
	if (ret < 0) {
		printf("-->> In C++ getJniEnv: ERROR: cached_jvm->GetEnv failed\n");
		exit (1);
	}
    return env;
}

JNIEXPORT void JNICALL 
Java_org_apache_hadoop_mapred_JniTest_initIDs(JNIEnv *env, jclass cls) 
{
    MID_JniTest_callback = env->GetMethodID(cls, "callback", "()V");
    printf("In C++: Java callback method was found\n");

    printf("In C++: calling Java static callback method, using Jni's GentEnv \n");
    getJniEnv()->CallStaticVoidMethod(cls, MID_JniTest_staticCallback);
	
//    getJniEnv()->CallStaticVoidMethod(javaClass, MID_JniTest_staticCallback);
	
	
    printf("In C++: after calling Java static callback method \n");
}

JNIEXPORT void JNICALL 
Java_org_apache_hadoop_mapred_JniTest_nativeMethod(JNIEnv *env, jobject obj)
{
    printf("In C++ native method\n");
    env->CallVoidMethod(obj, MID_JniTest_callback);
}

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved)
{
	printf("-->> In C++ JNI_OnLoad\n");
    JNIEnv *env;
	jclass cls;
	cached_jvm = vm;

    if ( vm->GetEnv((void **)&env, JNI_VERSION_1_4)) { //direct buffer requires java 1.4
        return JNI_ERR; /* JNI version not supported */
    }
	
	cls = env->FindClass("org/apache/hadoop/mapred/JniTest");
    if (cls == NULL) {
		printf("-->> In C++ java class was NOT found\n");
        return JNI_ERR;
    }
	printf("-->> In C++ java class was found\n");
	
    /* Use weak global ref to allow C class to be unloaded */
    javaClass = env->NewWeakGlobalRef(cls);
    if (javaClass == NULL) {
		printf("-->> In C++ weak global ref to java class was NOT found\n");
        return JNI_ERR;
    }
  	
    MID_JniTest_staticCallback = env->GetStaticMethodID(cls, "staticCallback", "()V");

	if (MID_JniTest_staticCallback == NULL) {
		printf("-->> In C++ java static method was NOT found\n");
        return JNI_ERR;
    }

	printf("-->> In C++ java method was found and cached\n");
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
    env->DeleteWeakGlobalRef(javaClass);
    return;	
	
	return;
}

