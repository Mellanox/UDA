#!/bin/awk -f

function getDateValue (d){
        "date +%s -d \""d"\"" |getline date_val;
        return date_val
}

 
BEGIN{ 
	FS="[\]\/.:\[]"
} 

{ print $6 " " $7 " " $8 " " $9 " " $10 " " $11 " sample" $15 " " $16 " " $18 " " $((NF-2)) " " $((NF-1)) }

