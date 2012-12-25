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
// These classes were taken from: http://hadoop.apache.org/docs/current/api/org/apache/hadoop/io/WritableComparable.html
// TODO: analyze/support the rest of classes in the above page, such as DoubleWriteable and so on...
const char * TEXT_COMPARABLE[] = {
		"org.apache.hadoop.io.Text",
//		"org.apache.hadoop.io.BytesWritable",
		NULL};
const char * BYTE_COMPARABLE[] = {
		"org.apache.hadoop.io.BooleanWritable",
		"org.apache.hadoop.io.ShortWritable",
		"org.apache.hadoop.io.IntWritable",
		"org.apache.hadoop.io.LongWritable",
		NULL};


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
		log(lsFATAL, "using compare function for unsupported type: '%s'", java_comparator_type_name);
		throw new UdaException("using compare function for unsupported type");
	}
}

