#!/bin/awk -f
# IdanW - 28052013
# the script detmines hangs between log prints

function getDateValue (d){
        "date +%s -d \""d"\"" |getline date_val;
        return date_val
}

function mktime_bylogdate(d){ # 2013-05-28 07:48:55
	Y=$1
	M=$2
	D=$3
	H=$4
	Min=$5
	Sec=$6
	return mktime(Y" "M" "D" "H" "Min" "Sec);
}

BEGIN{
	if (length(MAX_DIFF) == 0) {
		MAX_DIFF=10
	}
	else if ((MAX_DIFF+0) != MAX_DIFF) { # indicates MAX_DIFF is not a number
		print "ERROR: MAX_DIFF="MAX_DIFF" - please use numeric value"
		exit
	}

	FS="[-: ,]"
	prevFile=""
} 

{ 
	rowNum++ 
	if (prevFile != FILENAME) {
		prevTime=0;
		rowNum=0;
		prevFile=FILENAME
	}
}

/^20/{ 

	currTime=mktime_bylogdate($1 " " $2);
	if ( prevTime != 0) { 
		timeDiff=currTime-prevTime
		if (timeDiff > MAX_DIFF) {
			printf ("%d sec ==>%s +%d\n",timeDiff,FILENAME, rowNum);
			#print prevRow
			#print $0
			#print " "
		}
	}
	prevTime=currTime
	prevRow=$0

}   
