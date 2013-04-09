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

#include "SnappyDecompressor.h"

snappy_status (*decompressor_func_ptr)(const char*, size_t, char*, size_t*);

SnappyDecompressor::SnappyDecompressor(int port, reduce_task_t* reduce_task) :
		DecompressorWrapper(port, reduce_task), libsnappy(NULL), snappy_loaded(
				false) {
	log(lsTRACE, "SnappyDecompressor CONSTRACTOR");
	initDecompress();
}

SnappyDecompressor::~SnappyDecompressor() {}

/**
 *
 */
void SnappyDecompressor::init() {
	log(lsTRACE, "snappy init");
	decompressor_func_ptr = (snappy_status (*)(const char*, size_t, char*,
			size_t*))loadSymbolWrapper(libsnappy,"snappy_uncompress");

}	/**
	 * loads snappy library
	 */
void SnappyDecompressor::initDecompress() {
	if (!snappy_loaded) {
		// Load libsnappy.so
		libsnappy = dlopen("libsnappy.so", RTLD_LAZY | RTLD_GLOBAL);
		if (!libsnappy) {
			log(lsERROR, "Error loading snappy library ,%s", dlerror());
			throw new UdaException("Error loading snappy library");
		}
		snappy_loaded = true;
	}
	init();
}

void SnappyDecompressor::decompress(const char* compressed_buff,
		char* uncompressed_buff, size_t compressed_buff_len,
		size_t uncompressed_buff_len, int /* offest - not in use for snappy */,
		decompressRetData_t* retObj) {

	snappy_status rc = decompressor_func_ptr(compressed_buff,
			compressed_buff_len, uncompressed_buff, &uncompressed_buff_len);
	switch (rc) {
	case SNAPPY_BUFFER_TOO_SMALL:
		log(lsERROR,
				"Could not decompress snappy data. Buffer length is too small.");
		break;
	case SNAPPY_INVALID_INPUT:
		log(lsERROR, "Could not decompress snappy data. Input is invalid.");
		break;
	case SNAPPY_OK:
		retObj->num_compressed_bytes = compressed_buff_len;
		retObj->num_uncompressed_bytes = uncompressed_buff_len;
		return;
		break;
	default:
		log(lsERROR, "Could not decompress snappy data.");
		break;
	}

	log(lsERROR, "Error=%d in snappy decompress function ", rc);
	throw new UdaException("Error in snappy decompress function");
}

void SnappyDecompressor::get_next_block_length(char* buf,decompressRetData_t* retObj) {
	uint32_t *tmp = (uint32_t*) buf;
	retObj->num_uncompressed_bytes = ntohl(tmp[0]);
	retObj->num_compressed_bytes = ntohl(tmp[1]);
}

uint32_t SnappyDecompressor::getNumCompressedBytes(char* buf) {
	return ntohl(((uint32_t*) buf)[1]);
}

uint32_t SnappyDecompressor::getNumUncompressedBytes(char* buf) {
	return ntohl((uint32_t) buf[0]);
}

uint32_t SnappyDecompressor::getBlockSizeOffset() {
	return 8;
}
