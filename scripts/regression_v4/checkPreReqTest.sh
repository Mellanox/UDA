#!/bin/bash

## NEED TO TAKE CARE OF:
# MIN_RAM_REQUIRED
# MAX_CPU_USAGE
echoPrefix=`eval $ECHO_PATTERN`

## Check RAM
for s in $SLAVES_BY_SPACES
do
	echo "$echoPrefix:*** Checking free RAM on $s"
	availableRam=`ssh $s cat /proc/meminfo | grep MemFree | awk '{print $2}'` # Get available ram in KB
	if (( $availableRam < $MIN_RAM_REQUIRED )); then
		echo "$echoPrefix: ${ECHO_BOLD}ERROR:${ECHO_NORMAL} Not enough free RAM on $s -  Need at least $MIN_RAM_REQUIRED KB but got only $availableRam KB"
		exit $EEC3
	else
		echo "$echoPrefix:RAM check OK on $s"
	fi
done


## Check CPU Usage
for s in $SLAVES_BY_SPACES
do
	echo "$echoPrefix:*** Checking CPU Usage on $s (average of 5 samples)"
	cpu="0"
	for i in {1..$CPU_USAGE_SAMPLES_TO_AVERAGE_COUNT};
	do
		cpuTmp=`ssh $s /usr/bin/top -b -n1 | grep "Cpu(s)" | awk '{ split($5,a,"%") ; print (100-a[1])/100'}`
		cpu=$(awk -v n1="$cpu" -v n2="$cpuTmp" 'BEGIN{print n1+n2}')
	done
	cpu=$(awk -v n1="$cpu" 'BEGIN{print n1/5}')
#	CPU=`ssh $s /usr/bin/top -b -n1 | grep "Cpu(s)" | awk '{ split($5,a,"%") ; print (100-a[1])/100'}`
	cpuCmp=$(awk -vn1="$cpu" -v n2="$MAX_CPU_USAGE" 'BEGIN{print (n1>n2)?1:0 }')
	echo "CPU usage on $s is $cpu"
	if [ "$cpuCmp" -eq 1 ] ; then
		echo "$echoPrefix: ${ECHO_BOLD}WARNING:${ECHO_NORMAL} CPU on $s Exceeds $MAX_CPU_USAGE"
	else
		echo "$echoPrefix:CPU usage check OK on $s"
	fi
done