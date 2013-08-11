#!/bin/bash

errorHandler ()
{
    if (($1==1));then
		echo "$echoPrefix: $2" | tee $ERROR_LOG
        exit $EEC1
	fi
}

chaceFlushManager ()
{	
	if ((`echo "$CACHE_FLUSHING_DATA_SIZE > 0" | bc` == 1));then
		ramSizeChaceFlushing
	fi
	tmp=$((lastDatasetNum+sample-1))
	currentData=$((tmp%GENERATE_COUNT + 1))
}

ramSizeChaceFlushing ()
{
	local nmaps=$((SLAVES_COUNT*MAX_MAPPERS))
	local dataSize=`echo "scale=0; $CACHE_FLUSHING_DATA_SIZE * $TERAGEN_GIGA_MULTIPLIER / 1" | bc` # DON'T REMOVE THAT "/ 1" ! the "scale=0" won't truncate the number without it 
	local cmd="bin/hadoop jar $HADOOP_EXAMPLES_JAR_EXP teragen -Ddfs.replication=1 -Dmapred.map.tasks=${nmaps} ${dataSize}"
	bash $SCRIPTS_DIR/generateData.sh "$cmd" "$CACHE_FLUSHING_DATA_DIR" "1" "$CACHE_FLUSHING_COUNT" "clear"
    errorHandler $? "Teragen Failed"
}

teragenning ()
{
#MAX_MAPPERS=16
	local nmaps=$((SLAVES_COUNT*MAX_MAPPERS))
	local dataSize=`echo "scale=0; $FINAL_DATA_SET * $TERAGEN_GIGA_MULTIPLIER / 1" | bc` # DON'T REMOVE THAT "/ 1" ! the "scale=0" won't truncate the number without it
	
	local cmd="bin/hadoop jar $HADOOP_EXAMPLES_JAR_EXP teragen -Ddfs.replication=$INPUT_DATA_REPLICATIONS_COUNT -Dmapred.map.tasks=${nmaps} ${dataSize}"
	echo "$echoPrefix: teragenning"
	bash $SCRIPTS_DIR/generateData.sh "$cmd" "$TERAGEN_DIR" "$GENERATE_COUNT" "$CURRENT_DATA_COUNT"
    errorHandler $? "Teragen Failed"
}

randomTextWriting ()
{
	local dataSize=`echo "scale=0; $FINAL_DATA_SET * $RANDOM_TEXT_WRITE_GIGA_MULTIPLIER / 1" | bc` # DON'T REMOVE THAT "/ 1" ! the "scale=0" won't truncate the number without it
	local cmd="bin/hadoop jar $HADOOP_EXAMPLES_JAR_EXP randomtextwriter $CMD_RANDOM_TEXT_WRITE_PARAMS -Ddfs.replication=$INPUT_DATA_REPLICATIONS_COUNT -Dtest.randomtextwrite.total_bytes=${dataSize}"

	echo "$echoPrefix: randomTextWriting"
	bash $SCRIPTS_DIR/generateData.sh "$cmd" "$RANDOM_TEXT_WRITE_DIR" "$GENERATE_COUNT" "$CURRENT_DATA_COUNT"
    errorHandler $? "RandomTextWriter Failed"
}

randomWriting ()
{
	local dataSize=`echo "scale=0; $FINAL_DATA_SET * $RANDOM_WRITE_GIGA_MULTIPLIER / 1" | bc` # DON'T REMOVE THAT "/ 1" ! the "scale=0" won't truncate the number without it
	local cmd="bin/hadoop jar $HADOOP_EXAMPLES_JAR_EXP randomwriter $CMD_RANDOM_WRITE_PARAMS -Ddfs.replication=$INPUT_DATA_REPLICATIONS_COUNT -Dtest.randomwrite.total_bytes=${dataSize}"
	
	echo "$echoPrefix: randomWriting"
	bash $SCRIPTS_DIR/generateData.sh "$cmd" "$RANDOM_WRITE_DIR" "$GENERATE_COUNT" "$CURRENT_DATA_COUNT"
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

restartingHadoop ()
{
	echo "$echoPrefix: restarting Hadoop"
	#formatOption=""
	#if (($FORMAT_DFS==1));then
	#	formatOption=" -restart"
	bash $SCRIPTS_DIR/start_hadoopExcel.sh "$@" #"$@ $formatOption"
	errorHandler $? "failed to restart Hadoop"
	return $?
}

generatingData()
{
	# generating the correct data-source for the test
	if (($TERAGEN == 1));then 
		if (($FORCE_DATA_GENERATION == 1));then
			bin/hadoop fs -rmr $TERAGEN_DIR
			teragenning
		elif ((`bin/hadoop fs -ls $TERAGEN_DIR | grep -c $CURRENT_DATA_COUNT*` == 0));then
			teragenning
		fi
	elif (($RANDOM_TEXT_WRITE == 1));then
		if (($FORCE_DATA_GENERATION == 1));then
			bin/hadoop fs -rmr $RANDOM_TEXT_WRITE_DIR
			randomTextWriting
		elif ((`bin/hadoop fs -ls $RANDOM_TEXT_WRITE_DIR | grep -c $CURRENT_DATA_COUNT*` == 0));then
			randomTextWriting
		fi
	elif (($RANDOM_WRITE == 1));then
		if (($FORCE_DATA_GENERATION == 1));then
			bin/hadoop fs -rmr $RANDOM_WRITE_DIR
			randomWriting
		elif ((`bin/hadoop fs -ls $RANDOM_WRITE_DIR | grep -c $CURRENT_DATA_COUNT` == 0));then
			randomWriting
		fi
	fi
}

currentLogsDir=$1
outputDir=$2
lastDatasetNum=$3

echoPrefix=`eval $ECHO_PATTERN`
clusterNodes=$SLAVES_COUNT
mappers=$MAX_MAPPERS
reducers=$MAX_REDUCERS

mkdir -p $currentLogsDir
echo "$echoPrefix: generating data for the $PROGRAM"
generatingData

for sample in `seq 1 $NSAMPLES`
do				
	attempt=1
	code=0
	attemptCode=1
	
	executionFolder=${TEST_DIR_PREFIX}${sample}${ATTEMPT_DIR_INFIX}${attempt}
	collectionTempDir=$TMP_DIR/$executionFolder
	collectionDestDir=$currentLogsDir/$executionFolder
	mkdir -p $collectionTempDir
	execLogExports=$collectionTempDir/execLogExports.sh
	
	while (($attemptCode!=0)) && (($attempt<=$EXECUTION_MAX_ATTEMPTS))
	do

		echo "$echoPrefix: Cleaning $outputDir HDFS library"
		echo "$echoPrefix: bin/hadoop fs -rmr $outputDir"
		bin/hadoop fs -rmr $outputDir
		sleep 10

		echo "$echoPrefix: Running test on cluster of $clusterNodes slaves with $mappers mappers, $reducers reducers per TT"
		# flushing the cache and cleaning log files
		if (($CACHE_FLUHSING == 1));then
			echo "$echoPrefix: Cleaning buffer caches" 
			sudo bin/slaves.sh $SCRIPTS_DIR/cache_flush.sh
		fi
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
		#if (($CACHE_FLUHSING == 1));then
		#	tmp=$((lastDatasetNum+sample-1))
		#	currentData=$((tmp%GENERATE_COUNT + 1))
		#	chaceFlush #################################################################################
		#else
		#	currentData=1
		#fi
		################
		currentData=1
		if (($CACHE_FLUHSING == 1));then
			chaceFlushManager
		fi
		################
		# this is the command to run:
		export TEST_INPUT_DIR="$dataDir/${CURRENT_DATA_COUNT}.${currentData}"
		export TEST_OUTPUT_DIR="$outputDir"
		export USER_CMD="$CMD_PREFIX $HADOOP_EXAMPLES_JAR_EXP $CMD_PROGRAM $CMD_D_PARAMS $COMPRESSION_D_PARAMETERS $TEST_INPUT_DIR $TEST_OUTPUT_DIR"
		#export USER_CMD="$CMD_PREFIX $CMD_JAR_EXP $CMD_PROGRAM $CMD_D_PARAMS $TEST_INPUT_DIR $TEST_OUTPUT_DIR"
		echo "$echoPrefix: the command is: $USER_CMD"
		
		if [[ $PROGRAM == "wordcount" ]];then
			export TEST_OUTPUT_DIR_VANILLA="${WORDCOUNT_DIR}${WORDCOUNT_TEST_HDFS_DIR_SUFFIX}"
			export USER_CMD_VANILLA="$CMD_PREFIX $HADOOP_EXAMPLES_JAR_EXP $CMD_PROGRAM $COMPRESSION_D_PARAMETERS"
			#export USER_CMD_VANILLA="$CMD_PREFIX $CMD_JAR_EXP $CMD_PROGRAM"
		fi
		
		export LOG_PREFIX="${LOG_PREFIX}.N${FINAL_DATA_SET}G.N${mappers}m.N${reducers}r.log.${sample}"
		job=$LOG_PREFIX
		echo "$echoPrefix: job=$LOG_PREFIX"

		# executing the job and making staticsics
		echo "$echoPrefix: calling mr-dstat for $USER_CMD"
		echo "$echoPrefix: attempt #${attempt}"
		bash $SCRIPTS_DIR/mr-dstatExcel.sh $collectionTempDir $collectionDestDir $executionFolder $execLogExports $outputDir
		attemptCode=$?
		#*****************#
		source $collectionDestDir/execLogExports.sh
		if [[ -n $SETUP_FAILURE ]];then
			exit $EEC2
		fi
		#*****************#
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
	done # while ((attemptCode!=0)) && ((attempt<=EXECUTION_MAX_ATTEMPTS))

	if (($attemptCode == 0))
	then
		echo "$echoPrefix: ${job}${ATTEMPT_DIR_INFIX}${attempt} SUCCESS"
	fi
	
	if (($TEST_RUN_FLAG == 1));then
		break
	fi
done # sample
	
if (($DELETE_DATA==1));then
	echo "$echoPrefix: deleting the datasets of $dataDir/$CURRENT_DATA_COUNT by user demand"
	bin/hadoop fs -rmr $dataDir/$CURRENT_DATA_COUNT*
fi

echo "export ${PROGRAM}_LAST_DATASET_NUM='$currentData'" >> $TMP_DIR/sortcountRunnerExports.sh
