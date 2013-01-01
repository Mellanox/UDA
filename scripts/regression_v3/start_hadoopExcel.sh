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

if [ -z "$MY_HADOOP_HOME" ]
then
        echo "$(basename $0): please export MY_HADOOP_HOME"
        exit 1 
fi

if [ -z "$SCRIPTS_DIR" ]
then
	SCRIPTS_DIR=$(dirname $0)
fi

if [ -z "$HADOOP_CONF_DIR" ] 
then
	HADOOP_CONF_DIR="$MY_HADOOP_HOME/conf"
fi

if [ ! -z $1 ] && [ $1 -eq $1 2>/dev/null ] # check if $1 is a number
then
	max_tries=$1
else
	echo "Usage: $(basename $0) <number of retries> -restart -teragen -save_logs"
	echo "	-restart 	: force stop-all and reformat dfs"
	echo "	-teragen 	: force restart and make teragen after all nodes are alive *** mkteragen.sh is going to be exec, please make sure that all relevant enviroment paramters are configured properly."
	echo "	-save_logs 	: do not delete logs files"
        exit 0 
fi

if [[ $@ = *-restart* ]] || [[ $@ = *-teragen* ]]
then
	restart=1
	echo "$(basename $0): FORCED RESTART - reformat DFS"
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
	if (( $curr_try > 1 )) || (( $restart ))
	then
		$SCRIPTS_DIR/reset_all.sh -format $ignore_logs_arg
	else
		$SCRIPTS_DIR/reset_all.sh $ignore_logs_arg
	fi

	if (($?!=0))
	then
		echo "$(basename $0): FATAL ERROR - reset_all returned with rc"
        	exit 1
	fi

	echo "$(basename $0): Starting Hadoop - try $curr_try"


	echo "$(basename $0): Starting DFS (Namenodes[secondary&primary] and Datanodes)"
	tmp=`bin/start-dfs.sh`
	echo -e $tmp

	if [ -z `echo $tmp | egrep -ic '(error|fail|ssh|running)'` ]
	then
		echo "$(basname $0): unexpected messages found while starting DFS"
		curr_try=$((curr_try + 1))
		continue
	fi

	safemod=`bin/hadoop dfsadmin -safemode get`
	attempt=0
	while [[ $safemod != *OFF  &&  $attempt -ne $NUMBER_OF_ATTEMPTS_LIVE_NODES  ]]
	do
		echo "$(basename $0): waiting to exit from safe mode attempt number $attempt."
		sleep 5
		safemod=`bin/hadoop dfsadmin -safemode get`
		attempt=$(( $attempt + 1 ))
	done


	if [ $attempt -eq $NUMBER_OF_ATTEMPTS_LIVE_NODES ]
	then
	        echo "$(basename $0): ERROR - still in safe mode after $NUMBER_OF_ATTEMPTS_LIVE_NODES attempts"
                curr_try=$((curr_try + 1))
                continue
	fi


	# count the number of unmarked hosts on slaves conf file 
	expected_number_nodes=`cat "$HADOOP_CONF_DIR/slaves" | grep ^[[:alnum:]] -c`

	actual_number_nodes=0
	attempt=0

	while [ $expected_number_nodes -ne $actual_number_nodes ] && [ $attempt -ne $NUMBER_OF_ATTEMPTS_LIVE_NODES ]
	do
		sleep 5
		if [ $actual_number_nodes -gt  $expected_number_nodes ]
		then
			echo "$(basename $0): ERROR too many data nodes are alive - please check for live nodes that are not on the slaves list"
	                curr_try=$((curr_try + 1))
        	        continue
		fi
		echo "$(basename $0): waiting for live datanodes attempt number $attempt. currently $actual_number_nodes/$expected_number_nodes are alive"
		actual_number_nodes=`bin/hadoop fsck -racks | grep "Number of data-nodes" | awk '{print $NF}'`
	        attempt=$(( $attempt + 1 ))
	done


	if [ $attempt -eq $NUMBER_OF_ATTEMPTS_LIVE_NODES ]
	then
		echo "$(basename $0): ERROR - no $expected_number_nodes datanodes alive after $NUMBER_OF_ATTEMPTS_LIVE_NODES attempts"
                curr_try=$((curr_try + 1))
                continue
	fi

	echo "$(basename $0): DFS is up : $actual_number_nodes/$expected_number_nodes datanodes are alive"

	echo "$(basename $0): Starting MapReduce (JobTracker and TaskTrackers)"
	tmp=`bin/start-mapred.sh`
	echo -e $tmp

	if [ -z `echo $tmp | egrep -ic '(error|fail|ssh|running)'` ]
	then
		echo "$(basname $0): unexpected messages found while starting MapReduce"
                curr_try=$((curr_try + 1))
                continue
	fi

	actual_number_nodes=0
	attempt=0

	while [ $expected_number_nodes -ne $actual_number_nodes ] && [ $attempt -ne $NUMBER_OF_ATTEMPTS_LIVE_NODES ]
	do
		sleep 5
		if [ $actual_number_nodes -gt  $expected_number_nodes ]
	        then
	                echo "$(basename $0):  ERROR too many tasktrackers are alive - please check for live nodes that are not on the slaves list"
					bin/stop-all.sh
	                curr_try=$((curr_try + 1))
	                continue
	        fi
		echo "$(basename $0): waiting for tasktrackers , attempt number $attempt. currently $actual_number_nodes/$expected_number_nodes are alive"
	        actual_number_nodes=`bin/hadoop job -list-active-trackers | grep "tracker" -c`
	        attempt=$(( $attempt + 1 ))
	done


	if [ $attempt -eq $NUMBER_OF_ATTEMPTS_LIVE_NODES ]
	then
	        echo "$(basename $0): no  $expected_number_nodes tasktrackers alive after $NUMBER_OF_ATTEMPTS_LIVE_NODES attempts"
                curr_try=$((curr_try + 1))
                continue
	fi

	echo "$(basename $0): MapReduce  is up : $actual_number_nodes/$expected_number_nodes tasktracker are alive"
	
	hadoop_is_up=1
done

if (($hadoop_is_up==1))
then
	echo "$(basename $0): all $expected_number_nodes nodes are alive"
	if [[  $@ = *-teragen* ]] 
	then
		$SCRIPTS_DIR/mkteragenExcel.sh
	fi
else
	echo "$(basename $0): ERROR - failed to start hadoop after $1 retries"
        exit 1
fi




