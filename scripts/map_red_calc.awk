#!/bin/awk -f

function init_vars(){
	upM=0;
	downM=0;
	upR=0;
	downR=0;
	endMerge=0;
}

function print_summary(){
        if ( upM != 0 && downM !=0 ) {
		print upM ",1,mapper" > "map_red_sum.txt";
		print downM ",-1,mapper" > "map_red_sum.txt"
        }
	else if ( upM !=0 ) {
		print upM ",0 ,mapperUnknown" > "map_red_sum.txt"
	}
	if ( upR != 0 && downR !=0 ) {
               print upR ",1,reducer" > "map_red_sum.txt";
               print downR ",-1,reducer" > "map_red_sum.txt";
	}
	else if ( upR !=0 ) {
        print upR ",0 ,reducerUnknown" > "map_red_sum.txt"
	}
	
	if ( endMerge != 0 ) {
		print endMerge ",0,endMerge" > "map_red_sum.txt";
	}
}

BEGIN { 
	FS="[,  ]";
	OFS=" ";
	IGNORECASE=1;
	init_vars();
	mergeFlag=0;
}

FNR==1 {
      if (prev_filename) {
               print_summary()
       }
       init_vars();
}


FNR > 1 {prev_filename = FILENAME}


FNR == 0 {
	init_vars();
	}

$0 ~ /ReduceTask metrics system started/ {
		upR=$2;
}



$0 ~ /ReduceTask metrics system stopped/ {
		downR=$2
}


$0 ~ /MapTask metrics system started/ {
		upM=$2
}


$0 ~ /MapTask metrics system stopped/ {
		downM=$2
}


$0 ~ /merge_do_merging_phase()/ {
	
	if ( $0 ~ /GOT/ && mergeFlag==0 ){
		endMerge=$1;
		mergeFlag=1;
	}
}
END {
	print_summary();
    }
