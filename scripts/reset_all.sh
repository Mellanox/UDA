#!/bin/bash
# Written by Idan Weinstein On 2011-7-19

if [ -z "$HADOOP_HOME" ]
then
        echo $(basename $0): "please export HADOOP_HOME"
        exit 1
fi

if [ -z "$HADOOP_CONF_DIR" ]
then 
	HADOOP_CONF_DIR=$HADOOP_HOME/conf
fi

cd $HADOOP_HOME



echo "$(basename $0): Stoping Hadoop"
bin/stop-all.sh
sleep 2 


echo "$(basename $0): kill java/python/c++ process"
sudo pkill '(java|python|NetMerger|MOFSupplier)'
sudo bin/slaves.sh pkill "'(java|python|NetMerger|MOFSupplier)'"
sleep 2

# check for processes that did not respond to termination signals
live_processes=$(( `bin/slaves.sh ps -e | grep -Ec '(MOFSupplier|NetMerger|java)'` + `ps -e | grep -Ec '(MOFSupplier|NetMerger|java)'`  ))  

if [ $live_processes != 0 ]
then
	echo "$(basename $0): process are still alive after kill --> using kill -9"
	sudo pkill -9 '(java|python|NetMerger|MOFSupplier)'
	sudo bin/slaves.sh pkill -9 "'(java|python|NetMerger|MOFSupplier)'"
fi

sleep 2
# check if after kill -9 there are live processes
live_processes=$(( `bin/slaves.sh ps -e | grep -Ec '(MOFSupplier|NetMerger|java)'` + `ps -e | grep -Ec '(MOFSupplier|NetMerger|java)'`  )) 

if [ $live_processes != 0 ]
then
	bin/slaves.sh ps -ef | grep -E '(MOFSupplier|NetMerger|java)'
	echo "$(basename $0): ERROR: failed to kill process"
	exit 1;
fi

if [[ $@ = *-ignore_logs ]]
then
        echo "$(basename $0): Ignore logs (reset_all won't delete them)"
else
        echo "$(basename $0): Clear logs dir"
        sudo rm -rf $HADOOP_HOME/logs/*
        sudo bin/slaves.sh rm -rf $HADOOP_HOME/logs/\*
fi

if [[  $@ = *-format* ]]
then

	echo "$(basename $0): removing /data2 - /data5 files"
	sudo rm -rf /data2/* /data3/* /data4/* /data5/*
	sudo bin/slaves.sh rm -rf /data2/* /data3/* /data4/* /data5/*

	echo "$(basename $0) formating namenode"
	format_output=`bin/hadoop namenode -format 2>&1`
	echo $format_output

	if [[ $format_output != *successfully* ]]
	then
		echo "$(basename $0): ERROR - failed to format DFS"
		exit 1;
	fi
	sleep 6

fi



exit 0;





