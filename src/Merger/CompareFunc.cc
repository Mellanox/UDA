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

#include "CompareFunc.h"

// Matches BytesWritable's definition of LENGTH_BYTES in Java
const int LENGTH_BYTES = 4;

////////////////////////////////////////////////////////////////////////////////
// Use the arrays below for defining whether a given type is a 
// text-comparable/byte-comparable/bytes-comparable (or none of the above)
//
const char * TEXT_COMPARABLE[] = {
		"org.apache.hadoop.io.Text",
		NULL};
const char * BYTE_COMPARABLE[] = {
		"org.apache.hadoop.io.BooleanWritable",
		"org.apache.hadoop.io.ByteWritable",
		"org.apache.hadoop.io.ShortWritable",
		"org.apache.hadoop.io.IntWritable",
		"org.apache.hadoop.io.LongWritable",
		NULL};
const char * BYTES_COMPARABLE[] = {
		"org.apache.hadoop.io.BytesWritable",
		NULL};

/*
 // unsupported yet - all are derived of WritableComparable
 // see http://hadoop.apache.org/docs/current/api/org/apache/hadoop/io/WritableComparable.html

org.apache.hadoop.io.DoubleWritable
org.apache.hadoop.io.FloatWritable

org.apache.hadoop.io.VIntWritable
org.apache.hadoop.io.VLongWritable
org.apache.hadoop.mapred.ID (based on int)

//*/


////////////////////////////////////////////////////////////////////////////////
static bool str_in_array(const char* str, const char *arr[]){
	for (; *arr; ++arr) {
		if (strcmp(str,*arr) == 0) {
			return true;
		}
	}
	return false;
}


////////////////////////////////////////////////////////////////////////////////
static inline int byte_compare_inline(char* key1, int len1, char* key2, int len2) {
	int cmp_res =  memcmp(key1, key2, ((len1 < len2) ? len1 : len2));
	return (cmp_res) ? (cmp_res) : (len1 - len2);
}

////////////////////////////////////////////////////////////////////////////////
static int byte_compare(char* key1, int len1, char* key2, int len2) {
	return byte_compare_inline(key1, len1, key2, len2);
}
        

////////////////////////////////////////////////////////////////////////////////
static int text_compare(char* key1, int len1, char* key2, int len2) {
	int k1_skip_bytes = StreamUtility::decodeVIntSize((int)(key1[0]));
	int k2_skip_bytes = StreamUtility::decodeVIntSize((int)(key2[0]));
	return byte_compare_inline(key1 + k1_skip_bytes, len1 - k1_skip_bytes, key2 + k2_skip_bytes, len2 - k2_skip_bytes);
}

////////////////////////////////////////////////////////////////////////////////
static int bytes_compare(char* key1, int len1, char* key2, int len2) {
	return byte_compare_inline(key1 + LENGTH_BYTES, len1 - LENGTH_BYTES, key2 + LENGTH_BYTES, len2 - LENGTH_BYTES);
}

////////////////////////////////////////////////////////////////////////////////

hadoop_cmp_func get_compare_func(const char* java_comparator_type_name) {

	if (str_in_array(java_comparator_type_name, TEXT_COMPARABLE)) {
		log(lsDEBUG, "using Text compare function");
		return text_compare;
	}
	else if (str_in_array(java_comparator_type_name, BYTE_COMPARABLE)) {
		log(lsDEBUG, "using byte compare function");
		return byte_compare;
	}
	else if (str_in_array(java_comparator_type_name, BYTES_COMPARABLE)) {
		log(lsDEBUG, "using BytesWritable compare function");
		return bytes_compare;
	}
	else {
		log(lsERROR, "using compare function for unsupported type: '%s'", java_comparator_type_name);
		throw new UdaException("using compare function for unsupported type");
	}
}

