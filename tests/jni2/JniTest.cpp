#include <jni.h>
#include <stdio.h>
#include "JniTest.h"  


jmethodID MID_JniTest_callback;
//jarray carr = NULL;
//void*  carr = NULL;
jbyte *carr1 = NULL;
jbyte *carr2 = NULL;
jbyte *carr3 = NULL;
jboolean isCopy;

JNIEXPORT void JNICALL 
Java_JniTest_initIDs(JNIEnv *env, jclass cls)
{
    MID_JniTest_callback =
        env->GetMethodID(cls, "callback", "()V");

	//carr = env->GetPrimitiveArrayCritical(arr, &isCopy);
}

JNIEXPORT void JNICALL 
Java_JniTest_nativeMethod(JNIEnv *env, jobject obj, jbyteArray arr1, jbyteArray arr2, jbyteArray arr3)
{
    printf(">>> In C++\n");
	
	
    carr1 = env->GetByteArrayElements(arr1, &isCopy);
    printf("isCopy=%d\n", (int)(isCopy!=JNI_FALSE));
    carr2 = env->GetByteArrayElements(arr2, &isCopy);
    printf("isCopy=%d\n", (int)(isCopy!=JNI_FALSE));
    carr3 = env->GetByteArrayElements(arr3, &isCopy);
    printf("isCopy=%d\n", (int)(isCopy!=JNI_FALSE));

    if (carr1 == NULL || carr2 == NULL || carr3 == NULL) {
		printf("GetByteArrayElements has failed\n");
        return; // exception occurred 
	}

	jsize len = env->GetArrayLength(arr3);
	for (int i = 0; i < len; ++i) {
		carr3[i] = carr1[i] | carr2[i];
	}

    env->CallVoidMethod(obj, MID_JniTest_callback);

	// TEST: this may print error in our java check() function
	// to fix that, put these 3 lines before above call to CallVoidMethod
	env->ReleaseByteArrayElements(arr1, carr1, 0);
	env->ReleaseByteArrayElements(arr2, carr2, 0);
	env->ReleaseByteArrayElements(arr3, carr3, 0);
		
    printf("<<< Exiting C++\n");
}


//GetByteArrayElements and ReleaseByteArrayElements.
//GetPrimitiveArrayCritical and ReleasePrimitiveArrayCritical. 
