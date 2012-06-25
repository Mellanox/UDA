#ifndef UdaBridge__H___
#define UdaBridge__H___

#ifdef __cplusplus
extern "C" {
#endif


#include <jni.h>
//forward declarations

struct index_record;

jobject UdaBridge_registerDirectByteBuffer(JNIEnv * jniEnv,  void* address, long capacity);
void UdaBridge_invoke_fetchOverMessage_callback(JNIEnv * jniEnv);
void UdaBridge_invoke_dataFromUda_callback(JNIEnv * jniEnv, jobject jbuf, int len);
index_record* UdaBridge_invoke_getPathUda_callback (JNIEnv * jniEnv, const char* job_id, const char* map_id, int reduceId);

// a utility function that attach the **current native thread** to the JVM and
// return the JNIEnv interface pointer for this thread
// BE CAREFUL:
// - DON'T call this function more than once for the same thread!!
// - DON'T use the handle from one thread in context of another thread!

JNIEnv *attachNativeThread();


#ifdef __cplusplus
}
#endif


#endif // ! UdaBridge__H___
