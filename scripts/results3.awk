#!/bin/awk -f


function getMinutes(minutes){
	leng=length(minutes);
	min=substr(minutes,2,leng-6);
	return min;
}

function getSeconds(seconds){
        leng=length(seconds);
        sec=substr(seconds,1,leng-4);
        return sec;
}

function init_vars(){
	error=0;
	nrSave=0;
	totalSeconds=0;
	cause="";
	date=0;
	fileName="";

}

function getFilenameFormat(fn){
        n=split(fn, fnSplit, "/");
        newName=fnSplit[n-1];
        gsub(/\./, ",", newName);
        return newName;
}

function print_summary(){
        totalSeconds=totalSeconds","
	fileName=getFilenameFormat(prev_filename);
        if ( error != 0 ) {
                cause=cause","
                printf("%s  %s +ERRORS: %s ", date, totalSeconds, cause)
                system("basename "fileName)

        }
        else {
             printf("%s  %s  +SUCCESS!!, ", date, totalSeconds)
             system("basename "fileName)
        }

}


BEGIN { 
	FS=" ";
	OFS=" ";
	IGNORECASE=1;
	init_vars();
}

FNR==1 {
      if (prev_filename) {
               print_summary()
       }
       init_vars()
}


FNR > 1 {prev_filename = FILENAME}


$0 ~ /Kind/ {
		nrSave=FNR
}


$1 == "Finished" {
	minutes=$5
	minutes=getMinutes(minutes);
	seconds=$6
	seconds=getSeconds(seconds);
	totalSeconds=minutes*60+seconds;
}


{
	if ( FNR == nrSave+2 && FNR != 2 ){
		if ( $4 == 0 && $5 ==0 ){
			date=$7" "$8","
		}
		else {
			error=2;
			cause="SetupError";
		}
	}

}

{ 
	if ( FNR == nrSave+3 && FNR != 3 ){
		if ( $4 == 0 && $5 ==0 ){
		}
		else {
			error=3;
			if ( cause != "" ){			
			cause=cause " ,MapError";
			}
			else cause="MapError"
		}
	}

}


{
	if ( FNR == nrSave+4 && FNR != 4 ){
		if ( $4 == 0 && $5 ==0 ){
		}
		else { 
			error=4;
                        if ( cause != "" ){
                        cause=cause " ,ReduceError";
                        }
			else cause="ReduceError"
		}
	}

}

{
	if ( FNR == nrSave+5 && FNR != 5 ){
		if ( $4 == 0 && $5 ==0 ){
		}
		else { 
			error=5;
                        if ( cause != "" ){
                        cause=cause " ,CleanupError";
                        }
			else cause="CleanupError";
		}
	}

}




END {
	print_summary();
}
