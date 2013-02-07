/*
 * SnappyDecompressor.cc
 *
 *  Created on: Nov 22, 2012
 *      Author: dinal
 */

#include "SnappyDecompressor.h"

snappy_status (*decompressor_func_ptr)(const char*, size_t, char*, size_t*);

SnappyDecompressor::SnappyDecompressor(int port, reduce_task_t* reduce_task):DecompressorWrapper (port, reduce_task){
	log(lsDEBUG,"SnappyDecompressor CONSTRACTOR");
	snappy_loaded=0;
	libsnappy = NULL;
}

/**
 *
 */
void SnappyDecompressor::init(){
	log(lsDEBUG,"snappy init");
	decompressor_func_ptr = (snappy_status (*)(const char*, size_t, char*, size_t*))loadSymbol(libsnappy,"snappy_uncompress");

}

/**
 * loads snappy library
 */
void SnappyDecompressor::initDecompress(){
	if(!snappy_loaded){
		dlerror();
		// Load libsnappy.so
		log(lsDEBUG,"loading libsnappy");
		void *libsnappy = dlopen("libsnappy.so", RTLD_LAZY | RTLD_GLOBAL);
		if (!libsnappy) {
			log(lsERROR,"Error loading snappy library ,%s",dlerror());
			throw new UdaException("Error loading snappy library");
		}
		snappy_loaded = 1;
	}
	init();
}

decompressRetData_t* SnappyDecompressor::decompress(char* compressed_buff, char* uncompressed_buff, size_t compressed_buff_len, size_t uncompressed_buff_len,int offest){
	//void* fptr = FUNC_PTR(decompressor_func_ptr);
	//log(lsDEBUG,"snappy decompress compressed_buff=%p uncompressed_buff=%p compressed_buff_len=%d uncompressed_buff_len=%d",compressed_buff,uncompressed_buff,compressed_buff_len,uncompressed_buff_len);
	snappy_status ret = decompressor_func_ptr(compressed_buff, compressed_buff_len, uncompressed_buff, &uncompressed_buff_len);
	if (ret == SNAPPY_BUFFER_TOO_SMALL){
		log(lsERROR,  "Could not decompress snappy data. Buffer length is too small.");
	} else if (ret == SNAPPY_INVALID_INPUT){
		log(lsERROR, "Could not decompress snappy data. Input is invalid.");
	} else if (ret != SNAPPY_OK){
		log(lsERROR,  "Could not decompress snappy data.");
	}else{ //everything ok
		log(lsDEBUG,"snappy decompressed ok, uncompressed_buff_len=%d",uncompressed_buff_len);
		decompressRetData_t* ret = new decompressRetData_t();
		ret->num_compressed_bytes=compressed_buff_len;
		ret->num_uncompressed_bytes=uncompressed_buff_len;
		return ret;
	}

	log(lsERROR,"Error=%d in snappy decompress function ", ret);
	throw new UdaException("Error in snappy decompress function");
}

decompressRetData_t* SnappyDecompressor::get_next_block_length(char* buf) {
	uint32_t tmp[2];
	memcpy(&tmp, buf, getBlockSizeOffset());
	decompressRetData_t* ret = new decompressRetData_t();

	ret->num_uncompressed_bytes=((tmp[0] & 0xFF000000)>>24);
	ret->num_uncompressed_bytes+=((tmp[0] & 0xFF0000)>>8);
	ret->num_uncompressed_bytes+=((tmp[0] & 0xFF00)<<8);
	ret->num_uncompressed_bytes+=((tmp[0] & 0xFF)<<24);

	ret->num_compressed_bytes=((tmp[1] & 0xFF000000)>>24);
	ret->num_compressed_bytes+=((tmp[1] & 0xFF0000)>>8);
	ret->num_compressed_bytes+=((tmp[1] & 0xFF00)<<8);
	ret->num_compressed_bytes+=((tmp[1] & 0xFF)<<24);

	return ret;

}

uint32_t SnappyDecompressor::getBlockSizeOffset (){ return 8;}

