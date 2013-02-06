/*
 * LzoDecompressor.h
 *
 *  Created on: Nov 20, 2012
 *      Author: dinal
 */

#ifndef LZODECOMPRESSOR_H_
#define LZODECOMPRESSOR_H_

#include "UdaBridge.h"
#include <string>
#include "../DataNet/RDMAClient.h"
#include <dlfcn.h>
#include "../DataNet/RDMAComm.h"
#include "DecompressorWrapper.h"

#include <lzo/lzo1.h>
#include <lzo/lzo1a.h>
#include <lzo/lzo1b.h>
#include <lzo/lzo1c.h>
#include <lzo/lzo1f.h>
#include <lzo/lzo1x.h>
#include <lzo/lzo1y.h>
#include <lzo/lzo1z.h>
#include <lzo/lzo2a.h>
#include <lzo/lzo_asm.h>


/* A helper macro to convert the java 'function-pointer' to a void*. */
#define FUNC_PTR(func_ptr) ((void*)((ptrdiff_t)(func_ptr)))

class LzoDecompressor : public DecompressorWrapper
{

public:

	void initDecompress();
	void decompress (char* compressed, int length);
	LzoDecompressor(int port, reduce_task_t* reduce_task);
	decompressRetData_t* get_next_block_length(char* buf);
	int getBlockSizeOffset ();
	decompressRetData_t* decompress(char* compressed_buff, char* uncompressed_buff, size_t compressed_buff_len, size_t uncompressed_buff_len,int offest);


private:
	void init();
	void loadDecompressorFunc();
//	void* loadSymbol(void *handle, char *symbol );

	char* decompressionParamName;
	int numOfDecompressFuncs;
	//char* decompressorFuncs[][2];
	void *liblzo2;
	int lzo_loaded ;
	void *decompressor_func_ptr;

};



#endif /* LZODECOMPRESSOR_H_ */
