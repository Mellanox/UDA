#include <jni.h>
#include <stdio.h>
#include <stdlib.h>
#include "org_apache_hadoop_mapred_JniTest.h"  

jmethodID MID_JniTest_callback;

JNIEXPORT void JNICALL 
Java_org_apache_hadoop_mapred_JniTest_initIDs(JNIEnv *env, jclass cls)
{
    MID_JniTest_callback =
        env->GetMethodID(cls, "callback", "()V");
		
	if (MID_JniTest_callback == NULL) {
	    printf("Method not found\n");
		exit (1); /* method not found */
    }
    printf("In C++: Java callback method was found\n");
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
	return JNI_VERSION_1_4;  //direct buffer requires java 1.4
}


extern "C" JNIEXPORT void JNICALL JNI_OnUnload(JavaVM *jvm, void *reserved)
{
	// NOTE: We never reached this place
	printf("-->> In C++ JNI_OnUnload\n");
	return;
}

