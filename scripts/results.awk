#!/bin/awk -f

function getDateValue (d){
        "date +%s -d \""d"\"" |getline date_val;
        return date_val
}

function getDate(){
        split($0, a, "at:");
        return a[2]
}

function getFilenameFormat(fn){
	n=split(fn, fnSplit, "/");
	newName=fnSplit[n-1];
	gsub(/\./, ",", newName);
        return newName;
}

BEGIN { 
	OFS=",";
}

/started/{d1 = getDateValue(getDate())}

/ended/  {
	print getFilenameFormat(FILENAME), getDateValue(getDate()) - d1 ;
#	system("sudo grep -ir -E \"error|fail|exception\" $(dirname "FILENAME") | wc -l"); 
}

