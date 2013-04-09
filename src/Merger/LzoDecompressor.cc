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

#include "LzoDecompressor.h"
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

using namespace std;

// [decompress func type, decompress function for this type]
string decompressorFuncs[][2] = {
{"LZO1","lzo1_decompress"},
{"LZO1A","lzo1a_decompress"},
{"LZO1B","lzo1b_decompress"},
{"LZO1B_SAFE","lzo1b_decompress_safe"},
{"LZO1C","lzo1c_decompress"},
{"LZO1C_SAFE","lzo1c_decompress_safe"},
{"LZO1C_ASM","lzo1c_decompress_asm"},
{"LZO1C_ASM_SAFE","lzo1c_decompress_asm_safe"},
{"LZO1F","lzo1f_decompress"},
{"LZO1F_SAFE","lzo1f_decompress_safe"},
{"LZO1F_ASM_FAST","lzo1f_decompress_asm_fast"},
{"LZO1F_ASM_FAST_SAFE","lzo1f_decompress_asm_fast_safe"},
{"LZO1X","lzo1x_decompress"},
{"LZO1X_SAFE","lzo1x_decompress_safe"},
{"LZO1X_ASM","lzo1x_decompress_asm"},
{"LZO1X_ASM_SAFE","lzo1x_decompress_asm_safe"},
{"LZO1X_ASM_FAST","lzo1x_decompress_asm_fast"},
{"LZO1X_ASM_FAST_SAFE","lzo1x_decompress_asm_fast_safe"},
{"LZO1Y","lzo1y_decompress"},
{"LZO1Y_SAFE","lzo1y_decompress_safe"},
{"LZO1Y_ASM","lzo1y_decompress_asm"},
{"LZO1Y_ASM_SAFE","lzo1y_decompress_asm_safe"},
{"LZO1Y_ASM_FAST","lzo1y_decompress_asm_fast"},
{"LZO1Y_ASM_FAST_SAFE","lzo1y_decompress_asm_fast_safe"},
{"LZO1Z","lzo1z_decompress"},
{"LZO1Z_SAFE","lzo1z_decompress_safe"},
{"LZO2A","lzo2a_decompress"},
{"LZO2A_SAFE","lzo2a_decompress_safe"}
};

static const char* DECOMP_PARAM = "io.compression.codec.lzo.decompressor";
static const int NUM_DECOMP_FUNCS = sizeof(decompressorFuncs) /sizeof(decompressorFuncs[0]); //28;


LzoDecompressor::LzoDecompressor(int port, reduce_task_t* reduce_task):DecompressorWrapper (port, reduce_task), liblzo2(NULL), decompressor_func_ptr(NULL), lzo_loaded(false){
	log(lsDEBUG,"LzoDecompressor constractor - numOfDecompressFuncs=%d", NUM_DECOMP_FUNCS);
	initDecompress();
}

LzoDecompressor::~LzoDecompressor() {}

/**
 * loads lzo library
 */
void LzoDecompressor::initDecompress(){
	if(!lzo_loaded){
		// Load liblzo2.so
		liblzo2 = dlopen("liblzo2.so", RTLD_LAZY | RTLD_GLOBAL);
		if (!liblzo2) {
			log(lsERROR,"Error loading lzo library ");
			throw new UdaException("Error loading lzo library");
		}
		lzo_loaded = true;
	}
	init();
}


/**
 * call to lzo init func and loads decompression function
 */
void LzoDecompressor::init(){

	typedef int (__LZO_CDECL *lzo_init_t) (unsigned,int,int,int,int,int,int,int,int,int);

	lzo_init_t lzo_init_func = (lzo_init_t)loadSymbolWrapper(liblzo2, "__lzo_init_v2");

	if(lzo_init_func==NULL) return;
	log(lsDEBUG,"LOADED __lzo_init_v2");
	int rv = lzo_init_func(LZO_VERSION, (int)sizeof(short), (int)sizeof(int),
			  (int)sizeof(long), (int)sizeof(lzo_uint32), (int)sizeof(lzo_uint),
			  (int)lzo_sizeof_dict_t, (int)sizeof(char*), (int)sizeof(lzo_voidp),
			  (int)sizeof(lzo_callback_t));
	if (rv != LZO_E_OK) {
		log(lsERROR,"Error calling lzo_init");
		throw new UdaException("Error calling lzo_init");
	}

	loadDecompressorFunc();
}

/**
 * gets lzo decompress type from conf file by using jni and load it.
 * if doesn't exist in conf then loads LZO1X by default
 */
void LzoDecompressor::loadDecompressorFunc(){
	std::string lzo_decompressor_function =  UdaBridge_invoke_getConfData_callback (DECOMP_PARAM, "LZO1X");

	for(int i=0; i < NUM_DECOMP_FUNCS; i++){
		if(lzo_decompressor_function.compare(decompressorFuncs[i][0])==0){
			log(lsINFO,"lzo found function[%d]=%s", i, decompressorFuncs[i][0].c_str());
			decompressor_func_ptr = (lzo_decompress_t) loadSymbolWrapper(liblzo2,decompressorFuncs[i][1].c_str());
			return; //success
		}
	}

	//error
	log(lsERROR,"can't find lzo decompress function");
	throw new UdaException("can't find lzo decompress function");
}

void LzoDecompressor::decompress
(const char* compressed_buff, char* uncompressed_buff, size_t compressed_buff_len, size_t uncompressed_buff_len, int /* offest - not in use for lzo */, decompressRetData_t* retObj){

	lzo_uint uncomp_len = uncompressed_buff_len;
	int rv = decompressor_func_ptr((lzo_bytep)compressed_buff, (lzo_uint)compressed_buff_len,(lzo_bytep)uncompressed_buff, &uncomp_len,NULL);
	if (rv == LZO_E_OK) {
		retObj->num_compressed_bytes=compressed_buff_len;
		retObj->num_uncompressed_bytes=uncomp_len;
	} else {
		log(lsERROR,"Error=%d in lzo decompress function ", rv);
		throw new UdaException("Error in lzo decompress function");
	}
}

void LzoDecompressor::get_next_block_length(char* buf, decompressRetData_t* retObj){

	uint32_t *tmp = (uint32_t*)buf;
	retObj->num_uncompressed_bytes = ntohl(tmp[0]);
	retObj->num_compressed_bytes   = ntohl(tmp[1]);
}


uint32_t LzoDecompressor::getNumCompressedBytes(char* buf){
	return ntohl(((uint32_t*) buf)[1]);
}

uint32_t LzoDecompressor::getNumUncompressedBytes(char* buf){
	return ntohl((uint32_t)buf[0]);
}

uint32_t LzoDecompressor::getBlockSizeOffset (){ return 8;}
