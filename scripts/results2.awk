#!/bin/awk -f

function getDateValue (d){
     #   dd=`awk  -F'[ /]' '   { print $2"/"$3"/"$1" "$4 } '`;
	"date +%s -d \""d"\"" |getline date_val;
        return date_val
}

function getDate(){
        split($0, a, " ");
        return a[1]
}

function getFilenameFormat(fn){
	n=split(fn, fnSplit, "/");
	newName=fnSplit[n-1];
	gsub(/\./, ",", newName);
        return newName;
}

BEGIN { 
	FS="[/ ]";
	OFS=",";
	IGNORECASE=1;
	err=0;
}

{ if ( NR == 1) err=0; }

/Running job:/{ 
	jobstart_ts= getDateValue($2"/"$3"/"$1" "$4)
	start_time_str=$3"/"$2"/"$1" "$4
}

/map 100% reduce 0%/ { 
	mapend_ts=getDateValue($2"/"$3"/"$1" "$4);
	mapTime=mapend_ts-jobstart_ts
 }


$0 ~ /(error|fail|exception)/ {  err=1; }


/terasort.TeraSort: done/ {
	jobend_ts=getDateValue($2"/"$3"/"$1" "$4)
	reduceTime=jobend_ts-mapend_ts
	totalTime=jobend_ts-jobstart_ts
	if ( err > 0 ) {
		printf("%s - %d sec +ERRORS - ",start_time_str, totalTime)
		system("basename "FILENAME)
		err=0;
	}
	else {
		printf("%s - %d sec SUCCESS - ",start_time_str, totalTime)
		system("basename "FILENAME)
	}

}

/Job Failed/ {
	printf("%s - ------  FAILED  - ",start_time_str)
	system("basename "FILENAME)
}

