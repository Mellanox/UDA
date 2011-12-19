#include <jni.h>
#include <stdio.h>
#include <stdlib.h>
#include "JniTest.h"  

jmethodID MID_JniTest_callback;

JNIEXPORT void JNICALL 
Java_JniTest_initIDs(JNIEnv *env, jclass cls)
{
    MID_JniTest_callback =
        env->GetMethodID(cls, "callback", "()V");
		
	if (MID_JniTest_callback == NULL) {
	    printf("Method not found\n");
		exit (1); /* method not found */
    }
    printf("Method found\n");
    printf("In C\n");
}

JNIEXPORT void JNICALL 
Java_JniTest_nativeMethod(JNIEnv *env, jobject obj)
{
    printf("In C++\n");
    env->CallVoidMethod(obj, MID_JniTest_callback);
}
