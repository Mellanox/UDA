#include "LzoDecompressor.h"

using namespace std;

// [decompress func type, decompress function for this type]
//!!! IMPORTANT if adding new element to array or removing one - need to change numOfDecompressFuncs var
char* decompressorFuncs[][2] = {
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


LzoDecompressor::LzoDecompressor(int port, reduce_task_t* reduce_task):DecompressorWrapper (port, reduce_task){
	log(lsDEBUG,"CONSTRACTOR!");
	decompressionParamName = "io.compression.codec.lzo.decompressor";
	numOfDecompressFuncs = 28;
	liblzo2 = NULL;
	lzo_loaded = 0;
	//initDecompress();
}


/**
 * call to lzo init func and loads decompression function
 */
void LzoDecompressor::init(){
	log(lsDEBUG,"INIT!!!!!!!!!!!!!!!!!!");
	dlerror();

	typedef int (__LZO_CDECL *lzo_init_t) (unsigned,int,int,int,int,int,int,int,int,int);
	void *lzo_init_func_ptr = NULL;

	lzo_init_func_ptr = loadSymbol(liblzo2, "__lzo_init_v2");

	if(lzo_init_func_ptr==NULL) return;
	log(lsDEBUG,"LOADED __lzo_init_v2!!!!!!!!!!!!!!!!!!");
	lzo_init_t lzo_init_func = (lzo_init_t)(lzo_init_func_ptr);
	int rv = lzo_init_func(LZO_VERSION, (int)sizeof(short), (int)sizeof(int),
			  (int)sizeof(long), (int)sizeof(lzo_uint32), (int)sizeof(lzo_uint),
			  (int)lzo_sizeof_dict_t, (int)sizeof(char*), (int)sizeof(lzo_voidp),
			  (int)sizeof(lzo_callback_t));
	if (rv != LZO_E_OK) {
		log(lsERROR,"Error calling lzo_init");
		return;
	}

	loadDecompressorFunc();


}

/**
 * gets lzo decompress type from conf file by using jni and load it.
 * if doesn't exist in conf then loads LZO1X by default
 */
void LzoDecompressor::loadDecompressorFunc(){
	log(lsDEBUG,"getDecompressorFunc!!!!!!!!!!!!!!!!!!");
	initJniEnv();
	decompressor_func_ptr = NULL;
	char *lzo_decompressor_function =  UdaBridge_invoke_getConfData_callback(this->jniEnv, decompressionParamName, "LZO1X");
	log(lsDEBUG,lzo_decompressor_function);
	int i;
	//if wrong lzo decompressor function was specified - load default
	if(lzo_decompressor_function==NULL){
		log(lsERROR,"can't find lzo decompress function, using default LZO1X instead");
		lzo_decompressor_function = "LZO1X";
	}
	for(i=0; i< numOfDecompressFuncs; i++){
		if(strcmp(decompressorFuncs[i][0],lzo_decompressor_function)==0){
			log(lsDEBUG,"found name!!!!!!!!!!!!!!!!!!");
			decompressor_func_ptr = loadSymbol(liblzo2,decompressorFuncs[i][1]);
			break;
		}
	}
	free(lzo_decompressor_function);
}

/**
 * loads lzo library
 */
void LzoDecompressor::initDecompress(){
	log(lsDEBUG,"initDecompress!!!!!!!!!!!!!!!!!!");
	if(!lzo_loaded){
		// Load liblzo2.so
		log(lsDEBUG,"loading!!!!!!!!!!!!!!!!!!");
		liblzo2 = dlopen("liblzo2.so", RTLD_LAZY | RTLD_GLOBAL);
		if (!liblzo2) {
			log(lsERROR,"Error loading lzo library ");
			  return;
		}
		lzo_loaded = 1;
	}
	init();
}


decompressRetData_t* LzoDecompressor::decompress(char* compressed_buff, char* uncompressed_buff, size_t compressed_buff_len, size_t uncompressed_buff_len,int offest){
//decompressRetData_t* LzoDecompressor::decompress(lzo_bytep compressed_buff, lzo_bytep uncompressed_buff, lzo_uint compressed_buff_len, lzo_uint uncompressed_buff_len,int offest){
	lzo_decompress_t fptr = (lzo_decompress_t) FUNC_PTR(decompressor_func_ptr);
	lzo_uint uncomp_len = uncompressed_buff_len;
	int rv = fptr((lzo_bytep)compressed_buff, (lzo_uint)compressed_buff_len,(lzo_bytep)uncompressed_buff, &uncomp_len,NULL);
	if (rv == LZO_E_OK) {
		decompressRetData_t* ret = new decompressRetData_t();
		ret->num_compressed_bytes=compressed_buff_len;
		ret->num_uncompressed_bytes=uncomp_len;
		return ret;
	} else {
		log(lsERROR,"Error in lzo decompress function ");
		return NULL;
	}
}

int LzoDecompressor::get_next_block_length(char* buf) {
	return 100000;
}

int LzoDecompressor::getBlockSizeOffset (){ return 4;}

void LzoDecompressor::decompress (char* compressed, int length){
	memcpy (this->buffer, compressed, length);
	log(lsDEBUG, "bugg lll1 finished successfully");
}

