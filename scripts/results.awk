#!/bin/awk -f

function getDateValue (d){
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
	FS=" "
	OFS=",";
}


/Running job:/{ 
	jobstart_ts= getDateValue($2)
	start_time_str=$1","$2
	mapFlag=0
}

/map 100%/ { 
	if ( mapFlag == 0 ){
	mapend_ts=getDateValue($2);
	mapTime=mapend_ts-jobstart_ts
	print "aaaaaaaaaaa"
	mapFlag=1
	}
 }

/Job complete:/ {
	jobend_ts=getDateValue($2)
	reduceTime=jobend_ts-mapend_ts
	totalTime=jobend_ts-jobstart_ts
	print start_time_str","getFilenameFormat(FILENAME),"Mapers:"mapTime",Redcuers:"reduceTime",Total:"totalTime
#	system("grep -ir -E \"error|fail|exception\" $(dirname "FILENAME") | wc -l"); 
}

