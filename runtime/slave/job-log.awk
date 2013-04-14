#!/bin/awk -f

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
