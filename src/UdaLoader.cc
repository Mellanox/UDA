
#include <jni.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

int MergeManager_main(int argc, char* argv[]);

struct Args{
	int    argc;
	char** argv;
	Args(int _argc, char** _argv) : argc(_argc), argv(_argv){}
};

void* mainWrapper(void* data)
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
extern "C" JNIEXPORT jint JNICALL Java_org_apache_hadoop_mapred_UdaLoader_start  (JNIEnv *env, jclass cls, jobjectArray stringArray) {

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
    pthread_create(&thr, NULL, mainWrapper, pArgs);
    printf("exiting 'C++ from Java Thread'\n");
    return 0;
}


//direct buffer requires java 1.4
extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved)
{
	printf("-->> C++ Loaded\n");
	return JNI_VERSION_1_4;
}


extern "C" JNIEXPORT void JNICALL JNI_OnUnload(JavaVM *jvm, void *reserved)
{
	// NOTE: we need to check if We reached this place
	printf("<<-- C++ UnLoaded\n");
	return;
}

