#include "IOUtility.h"
#include "AIOHandler.h"
#include <pthread.h>
#include <sys/stat.h>
#include <stdio.h>
#include <sys/time.h>
#include <dirent.h>
#include <iostream>
#include <unistd.h>
#include <stdio.h>
#include <list>

#define MAX_FDS (512)
#define SKIP_CACHE_STEP_SIZE (1<<20)
typedef struct fd_s {
	int fd;
	long size;
} fd_s_t;

typedef struct submit_req {
	int		fd;
	long	file_offset;
	long	size;
	char*	buff;
	void*	aio_arg;
} submit_req_t;

int openMOFs(int numOfDirs, char* dirs[], fd_s_t fd_s_arr[], long& maxfsize, bool open_with_O_DIRECT);
int callback(void* data);
void Usage(const char* appName);

pthread_mutex_t readSizeLock;
pthread_cond_t testFinishCond;
long totalSize=0;
long readSize=0;


int main(int argc, char *argv[])
{
	fd_s_t fdsArr[MAX_FDS];
	int rc, fdCount;
	char* tmpBuff;
	long chunk_size, min_nr, nr, maxevents, nsecTimeout;
	timespec timeout;
	AIOHandler *aio;
	long aio_arg;
	struct timeval start_time;
	struct timeval end_time;
	long maxfsize=0;
	submit_req_t*	aio_requests;
	int reqIndex=0;
	bool sequentialTest = false;
	int numOfPathes;
	int	ios_per_submit;

	if (argc < 7){
		Usage(argv[0]);
		return -1;
	}

	try {
		min_nr=atol(argv[1]);
		nr=atol(argv[2]);
		maxevents=atol(argv[3]);
		nsecTimeout=atol(argv[4]);
		chunk_size=atol(argv[5]);
		ios_per_submit=atoi(argv[6]);
		numOfPathes= argc - 7;
		if (strcmp(argv[argc-1],"-sq") == 0) {
			sequentialTest=true;
			numOfPathes--;
		}
	}
	catch(...) {
		Usage(argv[0]);
		return -1;
	}

	printf("DEBUG: min_nr=%ld, nr=%ld, maxevents=%ld, nsec=%ld, chunk_size=%ld, ios_per_submit=%d\n", min_nr, nr, maxevents, nsecTimeout, chunk_size, ios_per_submit);

	pthread_mutex_init(&readSizeLock, NULL);
	pthread_cond_init(&testFinishCond, NULL);

	timeout.tv_nsec=nsecTimeout;
	timeout.tv_sec=0;
	aio = new AIOHandler(callback,maxevents,min_nr, nr, &timeout);


	fdCount=openMOFs(numOfPathes, argv + 7, fdsArr, maxfsize, !sequentialTest);
	aio_requests= (submit_req_t*)malloc(sizeof(submit_req_t)*fdCount*(maxfsize/chunk_size + 1));

	if (fdCount <= 0)
		return -1;

	posix_memalign((void**)&tmpBuff, 512, chunk_size);

	printf("%d file descriptors opened\n", fdCount);
	printf("Total size= %ld MB\n", totalSize/(1024*1024));

	long offset;
	long stepOffset;
	int areqIndex=0;
	std::list<fd_s_t> fdsList;
	std::list<fd_s_t>::iterator iter;
	int randIndex;
	fd_s_t currFds;

	srand ( time(NULL) );
	for(stepOffset=0; stepOffset < SKIP_CACHE_STEP_SIZE; stepOffset+=chunk_size) {
		for(offset=stepOffset; offset < maxfsize; offset+=SKIP_CACHE_STEP_SIZE) {
			//		fdsList.clear();
			//		for(int i=0; i<fdCount; i++) {
			//			fdsList.push_front(fdsArr[i]);
			//		}
			//
			//		while (fdsList.size() > 0){
			//
			//			// getting random fd
			//			iter = fdsList.begin();
			//			randIndex = rand() % fdsList.size();
			//			std::advance(iter, randIndex);
			//			currFds=*iter;
			//			fdsList.erase(iter);
			//
			//			if (offset < currFds.size)	{
			//				aio_requests[reqIndex].buff=tmpBuff;
			//				aio_requests[reqIndex].fd=currFds.fd;
			//				aio_requests[reqIndex].file_offset=offset;
			//
			//				if (offset <= currFds.size-chunk_size)
			//					aio_arg=new int(chunk_size);
			//				else
			//					aio_arg=new int(currFds.size-offset);
			//
			//				aio_requests[reqIndex].aio_arg=(void*)aio_arg;
			//				aio_requests[reqIndex].size=*aio_arg;
			//
			//				reqIndex++;
			//			}

			for(int i=0; i<fdCount; i++) {

				if (offset < fdsArr[i].size)	{
					aio_requests[reqIndex].buff=tmpBuff;
					aio_requests[reqIndex].fd=fdsArr[i].fd;
					aio_requests[reqIndex].file_offset=offset;

					if (offset <= fdsArr[i].size-chunk_size)
						aio_arg=chunk_size;
					else
						aio_arg=fdsArr[i].size-offset;

					aio_requests[reqIndex].aio_arg=(void*)aio_arg;
					aio_requests[reqIndex].size=aio_arg;

					reqIndex++;
				}


			}

		}
	}
	printf("press any key to start\n");
	//getchar();
	gettimeofday(&start_time,NULL);

	int reqCount=reqIndex;

	if (sequentialTest) {
		for (reqIndex=0; reqIndex<reqCount; reqIndex++) {
		    lseek(aio_requests[reqIndex].fd, aio_requests[reqIndex].file_offset, SEEK_SET);
			if ((rc=read(aio_requests[reqIndex].fd, aio_requests[reqIndex].buff , aio_requests[reqIndex].size) <=0)){
				output_stderr("[%s,%d] io_submit (read) failure: rc=%d - fd=%d , fileOffset=%ld, sizeToRead=%ld",__FILE__,__LINE__, rc, aio_requests[reqIndex].fd, aio_requests[reqIndex].file_offset, aio_requests[reqIndex].size);
				exit(-1);
			}

			if ((rc = callback(aio_requests[reqIndex].aio_arg))) {
				output_stderr("[%s,%d] failed to run sequentially callback after read operation. failure: rc=%d - fd=%d , fileOffset=%ld, sizeToRead=%ld",__FILE__,__LINE__, rc, aio_requests[reqIndex].fd, aio_requests[reqIndex].file_offset, aio_requests[reqIndex].size);
				exit(-1);

			}

		}
	}
	else {
		if (aio->start()) {
			output_stderr("Failed to start AIO Handler\n");
			return -1;
		}


		for (reqIndex=0; reqIndex<reqCount; reqIndex++) {
			aio->prepare_read(aio_requests[reqIndex].fd, aio_requests[reqIndex].file_offset, aio_requests[reqIndex].size, aio_requests[reqIndex].buff, aio_requests[reqIndex].aio_arg);

			if ((reqIndex>0) && ((reqIndex%ios_per_submit) == 0)) {
				aio->submit();
			}
		}

		aio->submit();

		pthread_mutex_lock(&readSizeLock);
		if (readSize<totalSize) {
			pthread_cond_wait(&testFinishCond, &readSizeLock);
		}
		else {
			printf("AIO Handler finished the submitted IO operations very close to the submition time\n");
		}
		pthread_mutex_unlock(&readSizeLock);

	}


	gettimeofday(&end_time,NULL);

	for(int i=0; i<fdCount; i++) {
		close(fdsArr[i].fd);
	}


	double start = start_time.tv_sec + (end_time.tv_usec /1000/1000);
	double end = end_time.tv_sec + (end_time.tv_usec /1000/1000);
	double diff = end - start;

	printf("***MODE: %s\n", (sequentialTest) ? "SEQUENTIAL" : "AIO with O_DIRECT");
	printf("START TIME: %f\n", start);
	printf("END TIME: %f\n", end);
	printf("TOTAL seconds: %f\n", diff);
	printf("TOTAL READ BYTES: %ld\n" , totalSize);
	printf("BW: %f MBpS\n" , totalSize/diff/1024/1024);

	fdsList.clear();
	delete aio;
	free(tmpBuff);

	return 0;
}




int callback(void* data) {
	long currSize=(long)data;

	pthread_mutex_lock(&readSizeLock);
	readSize+=currSize;
	printf("****************************************************************************************TOTAL: %ld/%ld\n", readSize, totalSize);
	if (readSize>=totalSize) {
		pthread_cond_signal(&testFinishCond);
	}
	pthread_mutex_unlock(&readSizeLock);


	return 0;

}

void Usage(const char* appName) {
	printf("Usage: %s <min_nr> <nr> <maxevents> <timeout> <chunk_size> <ios_per_submit> <mofs_path1> [<mofs_path2> ... <mofs_pathK>] -sq\n", appName);
	printf("\tThe test prepare AIO read requests for all files in <mofs_path1>..<mofs_pathK> using chunks of <chunk_size> and measures how long it takes\n");
	printf("\tEvery <ios_per_submit> requests are submitted together in one submit call\n");
	printf("\tFor testing multi HD , chose mofs_pathes smoothly from different spindles\n");
	printf("\tAIO context will be initialize with <maxevents>, io_getevents will be blocked for atleast <min_nr> and max <nr> or timeout of <timeout> nSec\n");
	printf("\tAdd '-sq' at the end for performing this test sequentially using blocking read operations and ignoring O_DIRECT flag when open file for reading\n");
}


int openMOFs(int numOfDirs, char* dirs[], fd_s_t fd_s_arr[], long& maxfsize, bool open_with_O_DIRECT) {
	struct dirent *ent;
	DIR* dir;
	int fdCount=0;
	struct stat fs;
	char fullpath[256];

	totalSize=0;

	printf("Open files:\n");

	for (int i=0; i < numOfDirs ; i++) {
		printf("\t%s\t", dirs[i]);

		dir = opendir(dirs[i]);
		if (dir == NULL) {
			printf("FAIL to open dir\n");
			return -1;
		}
		printf("OK\n");
		while ((ent = readdir(dir)) != NULL) {
			if (strcmp(ent->d_name, "..") &&  strcmp(ent->d_name, ".") ) {
				printf ("\t\t%s\t", ent->d_name);
				sprintf(fullpath, "%s/%s",dirs[i], ent->d_name);
				if (open_with_O_DIRECT)
					fd_s_arr[fdCount].fd=open(fullpath, O_RDONLY | O_DIRECT);
				else
					fd_s_arr[fdCount].fd=open(fullpath, O_RDONLY);

				if (fd_s_arr[fdCount].fd <= 0) {
					printf("FAIL to open file\n");
					return -1;
				}

				fstat(fd_s_arr[fdCount].fd,&fs);
				fd_s_arr[fdCount].size=fs.st_size;
				totalSize+=fs.st_size;
				if (fs.st_size > maxfsize)
					maxfsize=fs.st_size;

				printf("OK - size=%ld %s\n", fs.st_size, (open_with_O_DIRECT) ? "(O_DIRECT)" : "");
				fdCount++;
			}
		}
		closedir (dir);
		dir=NULL;
	}

	return fdCount;

}







