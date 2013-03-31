/*
 * SnappyDecompressor.h
 *
 *  Created on: Nov 22, 2012
 *      Author: dinal
 */

#include "UdaBridge.h"
#include <string>
#include "../DataNet/RDMAClient.h"
#include <dlfcn.h>
#include "../DataNet/RDMAComm.h"
#include "DecompressorWrapper.h"
#include "snappy-c.h"

#ifndef SNAPPYDECOMPRESSOR_H_
#define SNAPPYDECOMPRESSOR_H_

class SnappyDecompressor : public DecompressorWrapper
{
	public:

		SnappyDecompressor(int port, reduce_task_t* reduce_task);

	private:

		void init();
		void loadDecompressorFunc();
		void initDecompress();
		void get_next_block_length(char* buf, decompressRetData_t* retObj);
		uint32_t getBlockSizeOffset ();
		void decompress(const char* compressed_buff, char* uncompressed_buff, size_t compressed_buff_len, size_t uncompressed_buff_len, int /*offest*/, decompressRetData_t* retObj);
		uint32_t getNumCompressedBytes(char* buf);
		uint32_t getNumUncompressedBytes(char* buf);
		~SnappyDecompressor();

		void *libsnappy;
		bool snappy_loaded;

};

#endif /* SNAPPYDECOMPRESSOR_H_ */
