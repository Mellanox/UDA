#!/bin/bash
# Written by Idan Weinstein On 2011-7-19

if [ -z "$MY_HADOOP_HOME" ]
then
        echo $(basename $0): "please export MY_HADOOP_HOME"
        exit 1
fi

if [ -z "$HADOOP_CONFIGURATION_DIR" ]
then 
	HADOOP_CONFIGURATION_DIR=$MY_HADOOP_HOME/conf
fi

cd $MY_HADOOP_HOME



echo "$(basename $0): Stoping Hadoop"
bin/stop-all.sh
sleep 2 


echo "$(basename $0): kill java/python/c++ process"
pkill '(java|python|NetMerger|MOFSupplier)'
bin/slaves.sh pkill \'\(java\|python\|NetMerger\|MOFSupplier\)\'
sleep 2

# check for processes that did not respond to termination signals
live_processes=$(( `bin/slaves.sh ps -e | egrep -c '(MOFSupplier|NetMerger|java)'` + `ps -e | egrep -c '(MOFSupplier|NetMerger|java)'`  )) 

if [ $live_processes != 0 ]
then
	echo "$(basename $0): process are still alive after kill --> using kill -9"
	pkill -9 '(java|python|NetMerger|MOFSupplier)'
	bin/slaves.sh pkill -9 \'\(java\|python\|NetMerger\|MOFSupplier\)\'
fi

sleep 2
# check if after kill -9 there are live processes
live_processes=$(( `bin/slaves.sh ps -e | egrep -c '(MOFSupplier|NetMerger|java)'` + `ps -e | egrep -c '(MOFSupplier|NetMerger|java)'`  ))  

if [ $live_processes != 0 ]
then
	#echo "LIVA PROCESSES ARE: " `bin/slaves.sh ps -e | egrep '(MOFSupplier|NetMerger|java)'`
	#echo `ps -e | egrep '(MOFSupplier|NetMerger|java)'`  
	defunct_processes=$((`ps -e | egrep '(MOFSupplier|NetMerger|java)' | egrep -c '\<defunct\>'` + `bin/slaves.sh ps -e | egrep '(MOFSupplier|NetMerger|java)'| egrep -c '\<defunct\>' `))
	#echo defunct_processes: $defunct_processes
	if (($live_processes > $defunct_processes))
	then
		#bin/slaves.sh ps -ef | grep -E '(MOFSupplier|NetMerger|java)'
		echo "$(basename $0): ERROR: failed to kill processes"
		exit 1;
	fi
fi

if [[ $@ = *-ignore_logs ]]
then
        echo "$(basename $0): Ignore logs (reset_all won't delete them)"
else
        echo "$(basename $0): Clear logs dir"
        rm -rf $MY_HADOOP_HOME/logs/*
        bin/slaves.sh rm -rf $MY_HADOOP_HOME/logs/\*
fi

if [[  $@ = *-format* ]]
then

	#echo "$(basename $0): removing /data2 - /data5 files"

	echo "$(basename $0) formating namenode"
	echo "going to fm_part"
	$(dirname $0)/fm_part.sh 
	format_ans=$?
	if (( $format_ans==5 ));
	then
		echo "format failed!!"
		exit $SEC
	fi
	#format_output=`bin/hadoop namenode -format 2>&1`
	#echo $format_output

	#if [[ $format_output != *successfully* ]]
	#then
	#	echo "$(basename $0): ERROR - failed to format DFS"
	#	exit 1;
	#fi
	sleep 6

fi


exit 0;





