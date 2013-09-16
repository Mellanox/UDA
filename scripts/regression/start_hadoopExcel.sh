#!/bin/sh

#Writen by: Katya Katsenelenbogen
#Date: 19-7-2011


#Modified by IdanWe on 20-7-2011
#Script steps:
#	1. Retry loop
#	2. reset_all
#	3. format DFS in case of -restart or after 2 attempts 
#	1. Start DFS
#	2. Wait for DFS to exit safe-mode
#	3. Check for live datanodes
#	4. Start MR
#	5. Check for live TTs

#Modified by IdanWe on 10-10-2011
# - make teragen only if '-teragen' passed and not in any case of restart

echoPrefix=`eval $ECHO_PATTERN`	

retryAndCount()
{
	retryMessage=$1
	echo $retryMessage
	curr_try=$((curr_try + 1))
	continue
}


if [ ! -z $1 ] && [ $1 -eq $1 2>/dev/null ] # check if $1 is a number
then
	max_tries=$1
else
	echo "Usage: $(basename $0) <number of retries> -restart -teragen -save_logs"
	echo "	-restart 	: force stop-all and reformat dfs"
	echo "	-save_logs 	: do not delete logs files"
    exit 0
fi

if [[ $@ = *-restart* ]] || [[ $@ = *-teragen* ]] || (($FORMAT_DFS && ! $SAVE_HDFS_FLAG))
then
	restart=1
	echo "$echoPrefix: FORCED RESTART - reformat DFS"
else
	restart=0
fi

cd $MY_HADOOP_HOME

hadoop_is_up=0
curr_try=0

if [[ $@ = *-save_logs* ]]
then
	ignore_logs_arg="-ignore_logs"
else
	ignore_logs_arg=""
fi

while (( !$hadoop_is_up )) && (( $curr_try < $max_tries ))
do
	reset_all_flags="$ignore_logs_arg"
	if (( $curr_try > 1 )) || (( $restart ));then
		reset_all_flags="-format $reset_all_flags"
	fi
	echo "$echoPrefix: calling $SCRIPTS_DIR/reset_all.sh $reset_all_flags"
	$SCRIPTS_DIR/reset_all.sh $reset_all_flags
	if (($? != 0))
	then
		echo "$echoPrefix: FATAL ERROR - reset_all returned with rc"
		exit 1
	fi
	
	echo "$echoPrefix: Starting Hadoop - try $curr_try"
	echo "$echoPrefix: Starting DFS (Namenodes[secondary&primary] and Datanodes)"
	startDfsOutput=`eval $DFS_START`
	echo -e $startDfsOutput
	if [ -z `echo $startDfsOutput | egrep -ic '(error|fail|ssh|running)'` ]
	then
		retryAndCount "$echoPrefix: unexpected messages found while starting DFS"
	fi

	safemodeOutput=`eval $DFS_SAFEMODE_GET`
	attempt=0
	while [[ $safemodeOutput != *OFF  &&  $attempt -ne $NUMBER_OF_ATTEMPTS_LIVE_NODES  ]]
	do
		echo "$echoPrefix: waiting to exit from safe mode attempt number $attempt."
		sleep 5
		safemodeOutput=`eval $DFS_SAFEMODE_GET`
		attempt=$(( $attempt + 1 ))
	done
	if [ $attempt -eq $NUMBER_OF_ATTEMPTS_LIVE_NODES ]
	then
		retryAndCount "$echoPrefix: ERROR - still in safe mode after $NUMBER_OF_ATTEMPTS_LIVE_NODES attempts"
	fi

	actual_number_nodes=0
	attempt=0
	while [ $SLAVES_COUNT -ne $actual_number_nodes ] && [ $attempt -ne $NUMBER_OF_ATTEMPTS_LIVE_NODES ]
	do
		sleep 5
		if [ $actual_number_nodes -gt $SLAVES_COUNT ]
		then
			retryAndCount "$echoPrefix: ERROR too many data nodes are alive - please check for live nodes that are not on the slaves list"
		fi
		echo "$echoPrefix: waiting for live datanodes attempt number $attempt. currently $actual_number_nodes/$SLAVES_COUNT are alive"
		actual_number_nodes=`eval $DFS_FSCK_RACKS | grep "$DATANODE_INDICATOR" | awk '{print $NF}'`
		attempt=$(( $attempt + 1 ))
	done

	if [ $attempt -eq $NUMBER_OF_ATTEMPTS_LIVE_NODES ]
	then
		retryAndCount "$echoPrefix: ERROR - no $SLAVES_COUNT datanodes alive after $NUMBER_OF_ATTEMPTS_LIVE_NODES attempts"
	fi
	echo "$echoPrefix: DFS is up : $actual_number_nodes/$SLAVES_COUNT datanodes are alive"
	echo "$echoPrefix: Starting $MAPRED_SERVICE_NAME"
	mapredStartOutput=`eval $MAPRED_START`
	echo -e $mapredStartOutput
	if [ -z `echo $mapredStartOutput | egrep -ic '(error|fail|ssh|running)'` ]
	then
		retryAndCount "$echoPrefix: unexpected messages found while starting MapReduce"
	fi
	actual_number_nodes=0
	attempt=0
	while [ $SLAVES_COUNT -ne $actual_number_nodes ] && [ $attempt -ne $NUMBER_OF_ATTEMPTS_LIVE_NODES ]
	do
		sleep 5
		if [ $actual_number_nodes -gt  $SLAVES_COUNT ]
		then
			echo "$echoPrefix: ERROR too many tasktrackers are alive - please check for live nodes that are not on the slaves list"
			eval $HADOOP_STOP_ALL
			retryAndCount "$echoPrefix: Retrying"
		fi
		echo "$echoPrefix: waiting for tasktrackers , attempt number $attempt. currently $actual_number_nodes/$SLAVES_COUNT are alive"
		actual_number_nodes=`eval $JOB_OPTIONS -list-active-trackers | grep "$TASKTRACKER_INDICATOR" -c`
		attempt=$(( $attempt + 1 ))
	done

		if [ $attempt -eq $NUMBER_OF_ATTEMPTS_LIVE_NODES ]
		then
			retryAndCount "$echoPrefix: no  $SLAVES_COUNT tasktrackers alive after $NUMBER_OF_ATTEMPTS_LIVE_NODES attempts"
		fi
		echo "$echoPrefix: MapReduce  is up : $actual_number_nodes/$SLAVES_COUNT tasktracker are alive"
		hadoop_is_up=1
done

if (($hadoop_is_up==1))
then
	echo "$echoPrefix: all $SLAVES_COUNT nodes are alive"
else
	echo "$echoPrefix: ERROR - failed to start hadoop after $1 retries"
    exit 1
fi




