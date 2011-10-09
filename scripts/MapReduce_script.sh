#!/bin/sh

if [ $# -ne 1 ]; then
        echo "Usahge: ./script.sh <job_name>"
fi

time=0
count=0

echo "Map stat"

egrep "Initializing|done\.$" ${1}_m_*_0//syslog > /tmp/1

cat /tmp/1 |awk  'BEGIN {FS=" |:|,"} $10=="Initializing" {print $3*3600+ $4*60+ $5 , $10 }   $12=="done." {print  $3*3600+ $4*60+ $5 , $12 }' | sort -n > /tmp/2
#cat /tmp/1 |awk  'BEGIN {FS=" |:|,"} $10=="Initializing" {print $3*3600+ $4*60+ $5 "." $6, $10 }   $12=="done." {print  $3*3600+ $4*60+ $5 "." $6, $12 }' | sort -n > /tmp/2

cat /tmp/2 |while read line; do
	temp_time=`echo $line |awk 'BEGIN {FS=" "} {print $1}'`
	
	while [ "$temp_time" -gt "$time" ]; do
		time=$((time+1))
		echo $time $count
	done
	
	temp_op=`echo $line |awk 'BEGIN {FS=" "} {print $2}'`
	
	if [ "Initializing" == $temp_op ]
	then
		count=$((count+1))
	fi
	
	if [ "done." == $temp_op ]
	then
		count=$((count-1))
	fi
	
done

echo "Reduce stat"

time=0
count=0

egrep "Initializing|done\.$" ${1}_r_*_0//syslog > /tmp/1

cat /tmp/1 |awk  'BEGIN {FS=" |:|,"} $10=="Initializing" {print $3*3600+ $4*60+ $5 , $10 }   $12=="done." {print  $3*3600+ $4*60+ $5 , $12 }' | sort -n > /tmp/2
#cat /tmp/1 |awk  'BEGIN {FS=" |:|,"} $10=="Initializing" {print $3*3600+ $4*60+ $5 "." $6, $10 }   $12=="done." {print  $3*3600+ $4*60+ $5 "." $6, $12 }' | sort -n > /tmp/2

cat /tmp/2 |while read line; do
	temp_time=`echo $line |awk 'BEGIN {FS=" "} {print $1}'`

	while [ "$temp_time" -gt "$time" ]; do
		time=$((time+1))
		echo $time $count
	done

	temp_op=`echo $line |awk 'BEGIN {FS=" "} {print $2}'`

	if [ "Initializing" == $temp_op ]
	then
		count=$((count+1))
	fi

	if [ "done." == $temp_op ]
	then
		count=$((count-1))
	fi

done
