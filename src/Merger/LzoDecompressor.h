/*
** Copyright (C) 2012 Auburn University
** Copyright (C) 2012 Mellanox Technologies
**
** Licensed under the Apache License, Version 2.0 (the "License");
** you may not use this file except in compliance with the License.
** You may obtain a copy of the License at:
**
** http://www.apache.org/licenses/LICENSE-2.0
**
** Unless required by applicable law or agreed to in writing, software
** distributed under the License is distributed on an "AS IS" BASIS,
** WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
** either express or implied. See the License for the specific language
** governing permissions and  limitations under the License.
**
**
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
	virtual ~LzoDecompressor();

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
