#!/bin/bash

errorHandler (){
	# there is a scenario that error occured but the return value will be 0 - 
	# when start_hadoopExcel.sh or mkteragenExcel.sh prints their usage-print,
	# (which it a unsuccessfull scenario for this script's purposes).
	# in such case this script won't recognized the problem
    if (($1==1));then
		echo "$echoPrefix: $2" | tee $ERROR_LOG
        exit $EEC1
	fi
}

teragenning (){
	echo "$echoPrefix: Teragenning"
	bash $SCRIPTS_DIR/mkteragenExcel.sh
    errorHandler $? "Teragen Failed"
}

restartingHadoop (){
	echo "$echoPrefix: Restarting Hadoop"
	bash $SCRIPTS_DIR/start_hadoopExcel.sh $@ 
	errorHandler $? "failed to restart Hadoop"
	return $?
}

currentLogsDir=$1

echoPrefix=$(basename $0)
clusterNodes=$SLAVES_COUNT
mappers=$MAX_MAPPERS
reducers=$MAX_REDUCERS
dataSet=$TOTAL_DATA_SET
tatalTestsCounter=0

mkdir -p $currentLogsDir

if ((`bin/hadoop fs -ls / | grep -c $TERAGEN_DIR` == 0)) || (($TERAGEN == 1));then # if there is no teragen data or we need to generate a new one
	bin/hadoop fs -rmr $TERAGEN_DIR
	teragenning
fi

for sample in `seq 1 $NSAMPLES` ; do				
# delete this dummy
	#DATA_SET="16"
	ds_n=0
	for ds in $dataSet; do
		attempt=1
		code=0
		attemptCode=1
		ds_n=$((ds_n+1))
		tatalTestsCounter=$((tatalTestsCounter+1))
		
		while (($attemptCode!=0)) && (($attempt<$EXECUTION_MAX_ATTEMPTS))
		do

			echo "$echoPrefix: Cleaning $TERASORT_DIR HDFS library"
			echo "$echoPrefix: bin/hadoop fs -rmr $TERASORT_DIR"
			bin/hadoop fs -rmr $TERASORT_DIR
			sleep 10

			totalReducers=$(($clusterNodes * $reducers))
			if [[ $DATA_SET_TYPE == "node" ]];then
					totalDataSet=$(($ds * $clusterNodes))
			else
					totalDataSet=$ds
			fi

			echo "$echoPrefix: Running test on cluster of $clusterNodes slaves with $mappers mappers, $reducers reducers per TT and total of $totalReducers reducers"
			# flushing the cache and cleaning log files						
			echo "$echoPrefix: Cleaning buffer caches" 
			sudo bin/slaves.sh $SCRIPTS_DIR/cache_flush.sh
			#TODO: above will only flash OS cache; still need to flash disk cache
			sleep 3

			echo "$echoPrefix: Cleaning logs directories (history & userlogs)"
			rm -rf $MY_HADOOP_HOME/$USERLOGS_RELATIVE_PATH/*
			rm -rf $MY_HADOOP_HOME/$LOGS_HISTORY_RELATIVE_PATH/*
			bin/slaves.sh rm -rf $MY_HADOOP_HOME/$USERLOGS_RELATIVE_PATH/*
			bin/slaves.sh rm -rf $MY_HADOOP_HOME/$LOGS_HISTORY_RELATIVE_PATH/*

			# this is the command to run:
			export USER_CMD="$CMD_PREFIX $CMD_JAR $CMD_PROGRAM $CMD_D_PARAMS $TERAGEN_DIR/${totalDataSet}G.${ds_n} $TERASORT_DIR"
			echo "$echoPrefix: the command is: $USER_CMD"

			echo "$echoPrefix: job=${LOG_PREFIX}.N${ds}G.N${mappers}m.N${reducers}r.T${totalDataSet}G.T${totalReducers}r.log.${sample}"
			job=${LOG_PREFIX}.N${ds}G.${ds_n}.N${mappers}m.N${reducers}r.T${totalDataSet}G.T${totalReducers}r.log.${sample}

			# executing the job and making staticsics
			export INPUTDIR="$TERAGEN_DIR/${totalDataSet}G.${ds_n}"
			
			executionFolder=${TEST_DIR_PREFIX}${tatalTestsCounter}${SAMPLE_DIR_INFIX}${sample}${ATTEMPT_DIR_INFIX}${attempt}
			collectionTempDir=$TMP_DIR/$executionFolder
			collectionDestDir=$currentLogsDir/$executionFolder
			mkdir -p $collectionTempDir
			execLogExports=$collectionTempDir/execLogExports.sh

			echo "$echoPrefix: calling mr-dstat for $USER_CMD"
			echo "$echoPrefix: attempt #${attempt}"
			bash $SCRIPTS_DIR/mr-dstatExcel.sh $collectionTempDir $collectionDestDir $executionFolder $execLogExports $TERASORT_DIR
			attemptCode=$?

			if (($attemptCode != 0))
			then
				echo "$echoPrefix: attempt code: $attemptCode"
				echo "$echoPrefix: FAILED ${job}${ATTEMPT_DIR_INFIX}${attempt}"
				if (($attempt < 1))
				then
					echo "$echoPrefix: first attempt failed - don't restarting the hadoop yet"
				else									
					echo -n "$echoPrefix: more then one attempt failed - restart hadoop "

					if (($attempt == 0));then
						echo " without formatting the DFS"
						restartParam=""
					else
						echo " and formatting the DFS"
						restartParam=" -restart"
					fi
					restartingHadoop $RESTART_HADOOP_MAX_ATTEMPTS $restartParam

					if [[ $PROGRAM == "terasort" ]] && ((`bin/hadoop fs -ls / | grep -c $TERAGEN_DIR` == 0)); then
						teragenning
					fi
				fi
			fi
			
			attempt=$((attempt+1))			
		done # while ((attemptCode!=0)) && ((attempt<EXECUTION_MAX_ATTEMPTS))
	
		if (($attemptCode == 0))
		then
			echo "$echoPrefix: ${job}${ATTEMPT_DIR_INFIX}${attempt} SUCCESS"
		fi
		
		if (($TEST_RUN_FLAG == 1));then
			break
		fi
	done # ds
	if (($TEST_RUN_FLAG == 1));then
		break
	fi
done # sample