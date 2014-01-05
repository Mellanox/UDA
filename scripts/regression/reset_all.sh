#!/bin/bash
# Written by Idan Weinstein On 2011-7-19

echoPrefix=`eval $ECHO_PATTERN`

cd $MY_HADOOP_HOME

echo "$echoPrefix: Stoping Hadoop"
eval $DFS_STOP
eval $MAPRED_STOP
sleep 2 


echo "$echoPrefix: kill java/python/c++ process"
sudo pkill -9 '(java|python|NetMerger|MOFSupplier)'
sudo $EXEC_SLAVES pkill -9 \'\(java\|python\|NetMerger\|MOFSupplier\)\'
sleep 2

# check for processes that did not respond to termination signals
live_processes=$(( `eval $EXEC_SLAVES ps -e | egrep -c '(MOFSupplier|NetMerger|java)'` + `ps -e | egrep -c '(MOFSupplier|NetMerger|java)'`  )) 

if [ $live_processes != 0 ]
then
	echo LIVE PROCESSES ARE: $live_processes
	echo "$echoPrefix: process are still alive after kill --> using kill -9"
	sudo pkill -9 '(java|python|NetMerger|MOFSupplier)'
	sudo $EXEC_SLAVES pkill -9 \'\(java\|python\|NetMerger\|MOFSupplier\)\'
fi

sleep 2
# check if after kill -9 there are live processes
live_processes=$(( `eval $EXEC_SLAVES ps -e | egrep -c '(MOFSupplier|NetMerger|java)'` + `ps -e | egrep -c '(MOFSupplier|NetMerger|java)'`  ))  

if [ $live_processes != 0 ]
then
	echo "LIVE PROCESSES ARE (SECOND TIME):" $live_processes
	#echo "LIVA PROCESSES ARE: " `eval $EXEC_SLAVES ps -e | egrep '(MOFSupplier|NetMerger|java)'`
	#echo `ps -e | egrep '(MOFSupplier|NetMerger|java)'`  
	defunct_processes=$((`ps -e | egrep '(MOFSupplier|NetMerger|java)' | egrep -c '\<defunct\>'` + `eval $EXEC_SLAVES ps -e | egrep '(MOFSupplier|NetMerger|java)'| egrep -c '\<defunct\>' `))
	#echo defunct_processes: $defunct_processes
	if (($live_processes > $defunct_processes))
	then
		echo DEFUNCT PROCESSES ARE: `ps -e | egrep '(MOFSupplier|NetMerger|java)' | egrep '\<defunct\>'` `eval $EXEC_SLAVES ps -e | egrep '(MOFSupplier|NetMerger|java)'| egrep '\<defunct\>' `
		#eval $EXEC_SLAVES ps -ef | grep -E '(MOFSupplier|NetMerger|java)'
		echo "$echoPrefix: ERROR: failed to kill processes"
		exit 1;
	fi
fi

if [[ $@ = *-ignore_logs ]]
then
        echo "$echoPrefix: Ignore logs (reset_all won't delete them)"
else
        echo "$echoPrefix: Clear logs dir"
		for logDir in $HADOOP_LOGS_RELATIVE_DIR;do
			rm -rf $MY_HADOOP_HOME/$HADOOP_LOGS_RELATIVE_DIR/*
			eval $EXEC_SLAVES rm -rf $MY_HADOOP_HOME/$HADOOP_LOGS_RELATIVE_DIR/\*
		done
fi

if [[  $@ = *-format* ]]
then
	echo "$echoPrefix: formating namenode"
	bash $SCRIPTS_DIR/dfsManager.sh -r
	format_ans=$?
	if (( $format_ans==5 ));
	then
		echo "$echoPrefix: format failed!!"
		exit $SEC
	fi
	sleep 6
fi

exit 0





