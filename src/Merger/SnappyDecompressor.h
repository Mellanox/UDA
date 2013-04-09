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
		virtual ~SnappyDecompressor();

	private:

		void init();
		void loadDecompressorFunc();
		void initDecompress();
		void get_next_block_length(char* buf, decompressRetData_t* retObj);
		uint32_t getBlockSizeOffset ();
		void decompress(const char* compressed_buff, char* uncompressed_buff, size_t compressed_buff_len, size_t uncompressed_buff_len, int /*offest*/, decompressRetData_t* retObj);
		uint32_t getNumCompressedBytes(char* buf);
		uint32_t getNumUncompressedBytes(char* buf);


		void *libsnappy;
		bool snappy_loaded;

};

#endif /* SNAPPYDECOMPRESSOR_H_ */
