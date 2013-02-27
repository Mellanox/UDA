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

#include <lzo/lzoconf.h>

class LzoDecompressor : public DecompressorWrapper
{

public:

	LzoDecompressor(int port, reduce_task_t* reduce_task);

private:

	void init();
	void loadDecompressorFunc();
	void initDecompress();
	void get_next_block_length(char* buf, decompressRetData_t* retObj);
	uint32_t getBlockSizeOffset ();
	void decompress(const char* compressed_buff, char* uncompressed_buff, size_t compressed_buff_len, size_t uncompressed_buff_len, int offest, decompressRetData_t* retObj);
	uint32_t getNumCompressedBytes(char* buf);
	uint32_t getNumUncompressedBytes(char* buf);

	void *liblzo2;
	lzo_decompress_t decompressor_func_ptr;
	bool lzo_loaded ;
};

#endif /* LZODECOMPRESSOR_H_ */
