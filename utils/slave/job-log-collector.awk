#!/bin/awk -f
#
# Copyright (C) 2012 Mellanox Technologies
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at:
#  
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, 
# either express or implied. See the License for the specific language 
# governing permissions and  limitations under the License.
#
# 
# Written by Avner BenHanoch
# Date: 2013-04-25


BEGIN {
	if (!JOB) JOB = "201304091252_0001"
	if (!CONTEXT) CONTEXT = 1000 #lines
	if (!SUFFIX)  SUFFIX = ".job_" JOB ".snippet.x" # output filename(s) suffix
}

FNR==1 {
	
	FIRST = LAST = 0
	"grep -n " JOB " " FILENAME " | head -1 | awk -F: '{print $1}'" | getline FIRST
	"grep -n " JOB " " FILENAME " | tail -1 | awk -F: '{print $1}'" | getline LAST

	if (FIRST) { #job exist in file
		OUTFILE = FILENAME SUFFIX
		printf "%s: FIRST=%s, LAST=%s, OUTFILE=%s\n", ARGV[0], FIRST, LAST, FILENAME

		FIRST -= CONTEXT
		LAST  += CONTEXT
		printf "" > OUTFILE  # truncate output file
	}
	else {
		# printf "%s: === job=%s does NOT exist in file=%s\n", ARGV[0], JOB, FILENAME " ===" #debug 
			
		# optimization that may not be available in old versions of gawk; hence, it is commented out
		# nextfile 
	}
	
}

FIRST <= FNR && FNR <= LAST { print >> OUTFILE } # copy lines between FIRST and LAST
