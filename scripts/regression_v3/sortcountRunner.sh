#!/bin/bash

errorHandler (){
    if (($1==1));then
		echo "$echoPrefix: $2" | tee $ERROR_LOG
        exit $EEC1
	fi
}

teragenning (){
	local nmaps=$((SLAVES_COUNT*MAX_MAPPERS))
	#local dataSize=$((FINAL_DATA_SET*TERAGEN_GIGA_MULTIPLIER))
	local dataSize=`echo "$FINAL_DATA_SET*$TERAGEN_GIGA_MULTIPLIER * 1.0" | bc`
	dataSize=`echo "$dataSize" | sed s/.[^.]*$//`
	local cmd="bin/hadoop jar $HADOOP_EXAMPLES_JAR teragen -Dmapred.map.tasks=${nmaps} ${dataSize}"
	
	echo "$echoPrefix: teragenning"
	bash $SCRIPTS_DIR/generateData.sh "$cmd" $TERAGEN_DIR
    errorHandler $? "Teragen Failed"
}

randomTextWriting (){
	#local dataSize=$((FINAL_DATA_SET*RANDOM_TEXT_WRITE_GIGA_MULTIPLIER))
	local dataSize=`echo "$FINAL_DATA_SET * $RANDOM_TEXT_WRITE_GIGA_MULTIPLIER" | bc`
	dataSize=`echo "$dataSize" | sed s/.[^.]*$//`
	local cmd="bin/hadoop jar $HADOOP_EXAMPLES_JAR randomtextwriter $CMD_RANDOM_TEXT_WRITE_PARAMS -Dtest.randomtextwrite.total_bytes=${dataSize}"

	echo "$echoPrefix: randomTextWriting"
	bash $SCRIPTS_DIR/generateData.sh "$cmd" $RANDOM_TEXT_WRITE_DIR
    errorHandler $? "RandomTextWriter Failed"
}

randomWriting (){
	#local dataSize=$((FINAL_DATA_SET*RANDOM_WRITE_GIGA_MULTIPLIER))
	local dataSize=`echo "$FINAL_DATA_SET * $RANDOM_WRITE_GIGA_MULTIPLIER" | bc`
	dataSize=`echo "$dataSize" | sed s/.[^.]*$//`
	local cmd="bin/hadoop jar $HADOOP_EXAMPLES_JAR randomwriter $CMD_RANDOM_WRITE_PARAMS -Dtest.randomwrite.total_bytes=${dataSize}"
	
	echo "$echoPrefix: randomWriting"
	bash $SCRIPTS_DIR/generateData.sh "$cmd" $RANDOM_WRITE_DIR
    errorHandler $? "RandomWriter Failed"
}

#generatingData(){
#	cmd="$1"
#	dataDir="$2"
#	label="$3"
#	dataType="$4"
	
#	echo "$echoPrefix: generating data with $4"
#	bash $SCRIPTS_DIR/generateData.sh "$cmd" $dataDir $label
#   errorHandler $? "$4 Failed"
#}

restartingHadoop (){
	echo "$echoPrefix: restarting Hadoop"
	bash $SCRIPTS_DIR/start_hadoopExcel.sh $@ 
	errorHandler $? "failed to restart Hadoop"
	return $?
}

generatingData()
{
	# generating the correct data-source for the terasort
	if (($TERAGEN == 2));then
echo "POSITION 1"
		bin/hadoop fs -rmr $TERAGEN_DIR
		teragenning
	elif (($TERAGEN == 1)) && ((`bin/hadoop fs -ls $TERAGEN_DIR | grep -c $DATA_LABEL*` == 0));then
echo "POSITION 2"
		teragenning
	elif (($RANDOM_TEXT_WRITE == 2));then
echo "POSITION 3"
		bin/hadoop fs -rmr $RANDOM_TEXT_WRITE_DIR
		randomTextWriting
	elif (($RANDOM_TEXT_WRITE == 1)) && ((`bin/hadoop fs -ls $RANDOM_TEXT_WRITE_DIR | grep -c $DATA_LABEL*` == 0));then
echo "POSITION 4"
		randomTextWriting
	elif (($RANDOM_WRITE == 2));then
echo "POSITION 5"
		cd $MY_HADOOP_HOME
		bin/hadoop fs -rmr $RANDOM_WRITE_DIR
		randomWriting
	elif (($RANDOM_WRITE == 1)) && ((`bin/hadoop fs -ls $RANDOM_WRITE_DIR | grep -c $DATA_LABEL` == 0));then
echo "POSITION 6"
		randomWriting
#	elif ((`echo $TERASORT_DEFAULT_INPUT_DIR | grep -c "teragen"` == 1));then
#echo "POSITION 7"
		#teragenning
	#else
#echo "POSITION 8"
#		randomTextWriting
	fi
}

currentLogsDir=$1
outputDir=$2

echoPrefix=`eval $ECHO_PATTERN`
clusterNodes=$SLAVES_COUNT
mappers=$MAX_MAPPERS
reducers=$MAX_REDUCERS

mkdir -p $currentLogsDir
echo "$echoPrefix: generating data for the terasort"
generatingData

for sample in `seq 1 $NSAMPLES` ; do				

	#for ds in $dataSet; do
	attempt=1
	code=0
	attemptCode=1
	
	while (($attemptCode!=0)) && (($attempt<$EXECUTION_MAX_ATTEMPTS))
	do

		echo "$echoPrefix: Cleaning $outputDir HDFS library"
		echo "$echoPrefix: bin/hadoop fs -rmr $outputDir"
		bin/hadoop fs -rmr $outputDir
		sleep 10

		echo "$echoPrefix: Running test on cluster of $clusterNodes slaves with $mappers mappers, $reducers reducers per TT"
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

		# finding the correct data-source for the terasort
		if (($TERAGEN != 0));then
			dataDir=$TERAGEN_DIR
		elif (($RANDOM_TEXT_WRITE != 0));then
			dataDir=$RANDOM_TEXT_WRITE_DIR
		elif (($RANDOM_WRITE != 0));then
			dataDir=$RANDOM_WRITE_DIR
		else
			if [[ $PROGRAM == "terasort" ]];then
				dataDir=$TERASORT_DEFAULT_INPUT_DIR
			elif [[ $PROGRAM == "sort" ]];then
				dataDir=$SORT_DEFAULT_INPUT_DIR
			else
				dataDir=$WORDCOUNT_DEFAULT_INPUT_DIR
			fi
		fi
		# calculating the number of the next data to process
		tmp=$((sample-1))
		currentData=$((tmp%GENERATE_COUNT + 1))
		# this is the command to run:
		export TEST_INPUT_DIR="$dataDir/${DATA_LABEL}.${currentData}"
		export TEST_OUTPUT_DIR="$outputDir"
		export USER_CMD="$CMD_PREFIX $CMD_JAR $CMD_PROGRAM $CMD_D_PARAMS $TEST_INPUT_DIR $TEST_OUTPUT_DIR"
		echo "$echoPrefix: the command is: $USER_CMD"
		
		if [[ $PROGRAM == "wordcount" ]];then
			export TEST_OUTPUT_DIR_VANILLA="${WORDCOUNT_DIR}${WORDCOUNT_TEST_HDFS_DIR_POSTFIX}"
			export USER_CMD_VANILLA="$CMD_PREFIX $CMD_JAR $CMD_PROGRAM"
		fi
		
		export LOG_PREFIX="${LOG_PREFIX}.N${FINAL_DATA_SET}G.N${mappers}m.N${reducers}r.log.${sample}"
		echo "$echoPrefix: job=$LOG_PREFIX"

		# executing the job and making staticsics
		executionFolder=${TEST_DIR_PREFIX}${sample}${ATTEMPT_DIR_INFIX}${attempt}
		collectionTempDir=$TMP_DIR/$executionFolder
		collectionDestDir=$currentLogsDir/$executionFolder
		mkdir -p $collectionTempDir
		execLogExports=$collectionTempDir/execLogExports.sh

		echo "$echoPrefix: calling mr-dstat for $USER_CMD"
		echo "$echoPrefix: attempt #${attempt}"
		bash $SCRIPTS_DIR/mr-dstatExcel.sh $collectionTempDir $collectionDestDir $executionFolder $execLogExports $outputDir
		attemptCode=$?

		if (($attemptCode != 0))
		then
			echo "$echoPrefix: attempt code: $attemptCode"
			echo "$echoPrefix: FAILED ${job}${ATTEMPT_DIR_INFIX}${attempt}"
			if (($attempt == 1))
			then
				echo "$echoPrefix: first attempt failed - don't restarting the hadoop yet"
			else									
				echo -n "$echoPrefix: more then one attempt failed - restart hadoop "

				if (($attempt == 2));then
					echo " without formatting the DFS"
					restartParam=""
				else
					echo " and formatting the DFS"
					restartParam=" -restart"
				fi
				restartingHadoop $RESTART_HADOOP_MAX_ATTEMPTS $restartParam

				generatingData
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
done # sample