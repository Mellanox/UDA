#include <jni.h>
#include <stdio.h>
#include "JniTest.h"  

//
// for explanations - See README file!
//

jmethodID MID_JniTest_callback;
jmethodID MID_JniTest_dataFromUda_callback;

//jarray carr = NULL;
//void*  carr = NULL;
jbyte *carr1 = NULL;
jbyte *carr2 = NULL;
jbyte *carr3 = NULL;

jint fieldSIZE = 0;

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved)
{
	printf("-->> C++ Loaded\n");
	return JNI_VERSION_1_4;  //direct buffer requires java 1.4
}


extern "C" JNIEXPORT void JNICALL JNI_OnUnload(JavaVM *jvm, void *reserved)
{
	// NOTE: We never reached this place
	printf("<<-- C++ UnLoaded\n");
	return;
}

jbyte * getStaticDirectBuffer(JNIEnv *env, jclass cls, const char * fieldName)
{
    jfieldID fid = env->GetStaticFieldID(cls, fieldName, "Ljava/nio/ByteBuffer;");
    if (fid == 0) {
		printf("field not found\n");
        return NULL; /* field not found */
    }
	
    /* Access the static field */
    jobject jobj = env->GetStaticObjectField(cls, fid);
    return (jbyte*)env->GetDirectBufferAddress(jobj);
}

JNIEXPORT void JNICALL 
Java_JniTest_initIDs(JNIEnv *env, jclass cls)
{
    MID_JniTest_callback =
        env->GetMethodID(cls, "callback", "()V");
		
    MID_JniTest_dataFromUda_callback = env->GetStaticMethodID(cls, "dataFromUda", "(Ljava/lang/Object;I)V");

	const int SIZE = 1024 * 1024;
//	char buf[SIZE];
	char *buf = new char[SIZE];
	jobject jbuf = env->NewDirectByteBuffer(buf, SIZE);
    env->CallStaticVoidMethod(cls, MID_JniTest_dataFromUda_callback, jbuf, SIZE);
	delete[] buf;

	carr1 = getStaticDirectBuffer(env, cls, "barr1");
	carr2 = getStaticDirectBuffer(env, cls, "barr2");
	carr3 = getStaticDirectBuffer(env, cls, "barr3");
	
    if (carr1 == NULL || carr2 == NULL || carr3 == NULL) {
		printf("GetDirectBufferAddress has failed\n");
        return; // exception occurred 
	}
	
	
    jfieldID fid = env->GetStaticFieldID(cls, "SIZE", "I");
    if (fid == 0) {
		printf("field not found\n");
        return; /* field not found */
    }
	
    /* Access the static field */
    fieldSIZE = env->GetStaticIntField(cls, fid);	
}

extern "C" JNIEXPORT void JNICALL 
Java_JniTest_nativeMethod(JNIEnv *env, jobject obj)
{
    printf(">>> In C++\n");
	
	for (int i = 0; i < fieldSIZE; ++i) {
		carr3[i] = carr1[i] | carr2[i];
	}
    env->CallVoidMethod(obj, MID_JniTest_callback);

	printf("<<< Exiting C++\n");
}


//GetByteArrayElements and ReleaseByteArrayElements.
//GetPrimitiveArrayCritical and ReleasePrimitiveArrayCritical. 
