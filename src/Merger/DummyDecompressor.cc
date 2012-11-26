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

#include "DecompressorWrapper.h"

using namespace std;

class DummyDecompressor : public DecompressorWrapper
{
public:
	void initDecompress() {}
	void decompress (char* compressed, int length){
		memcpy (this->buffer, compressed, length);
//		log(lsDEBUG, "bugg lll1 finished successfully");
	}

	DummyDecompressor(int port, reduce_task_t* reduce_task):DecompressorWrapper (port, reduce_task){}

	int get_next_block_length(char* buf) {
		return 16000;
//		return 100000;
	}
	int getBlockSizeOffset (){ return 0;} //for LZO return 4;


	decompressRetData_t* decompress(char* compressed_buff, char* uncompressed_buff, size_t compressed_buff_len, size_t uncompressed_buff_len,int offest){
	//decompressRetData_t* LzoDecompressor::decompress(lzo_bytep compressed_buff, lzo_bytep uncompressed_buff, lzo_uint compressed_buff_len, lzo_uint uncompressed_buff_len,int offest){

			decompressRetData_t* ret = new decompressRetData_t();
			return ret;
	}




};







/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
