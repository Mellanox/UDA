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

////////////////////////////////////////////////////////////////////////////////
// Use the arrays below for defining whether a given type is a text-comparable, or a byte-comparable (or none of the above)
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

/*
 // unsupported yet - all are derived of WritableComparable
 // see http://hadoop.apache.org/docs/current/api/org/apache/hadoop/io/WritableComparable.html

org.apache.hadoop.io.BytesWritable
org.apache.hadoop.io.DoubleWritable
org.apache.hadoop.io.FloatWritable

org.apache.hadoop.io.VIntWritable
org.apache.hadoop.io.VLongWritable
org.apache.hadoop.mapred.ID (based on int)

//*/


////////////////////////////////////////////////////////////////////////////////
bool strInArray(const char* str, const char *arr[]){
	for (; *arr; ++arr) {
		if (strcmp(str,*arr) == 0) {
			return true;
		}
	}
	return false;
}

////////////////////////////////////////////////////////////////////////////////
int byte_compare(char* key1, int len1, char* key2, int len2) {
    int cmp_res =  memcmp(key1, key2, ((len1 < len2) ? len1 : len2));
	return (cmp_res) ? (cmp_res) : (len1 - len2);
}

////////////////////////////////////////////////////////////////////////////////
int java_text_compare(char* key1, int len1, char* key2, int len2) {
	int k1_skip_bytes = StreamUtility::decodeVIntSize((int)(key1[0]));
	int k2_skip_bytes = StreamUtility::decodeVIntSize((int)(key2[0]));
	return byte_compare(key1 + k1_skip_bytes, len1 - k1_skip_bytes, key2 + k2_skip_bytes, len2 - k2_skip_bytes);
}

////////////////////////////////////////////////////////////////////////////////
hadoop_cmp_func get_compare_func(const char* java_comparator_type_name) {

	if (strInArray(java_comparator_type_name, TEXT_COMPARABLE)) {
		log(lsDEBUG, "using Text compare function");
		return java_text_compare;
	}
	else if (strInArray(java_comparator_type_name, BYTE_COMPARABLE)) {
		log(lsDEBUG, "using byte compare function");
		return byte_compare;
	}
	else {
		log(lsERROR, "using compare function for unsupported type: '%s'", java_comparator_type_name);
		throw new UdaException("using compare function for unsupported type");
	}
}

