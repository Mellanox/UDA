#!/bin/bash

# Written by Avner BenHanoch
# Date: 2011-04-14
# Modified by IdanWe on 2011-06-07
#	- collect the results by using scp and not by using NFS mounts


#export HADOOP_SLAVE_SLEEP=0.1                        

getFiledDFSIO()
{
	getFiledDFSIO_retValue=`grep "$1" $testOutput | awk -v fieldSup="$1" 'BEGIN{FS=fieldSup};{print $2}'`
}

if [ -z "$MY_HADOOP_HOME" ]
then
	echo "please export MY_HADOOP_HOME"
	exit 1
fi

if [ -z "$SCRIPTS_DIR" ]
then
	echo "please export SCRIPTS_DIR (must be path on NFS)"
	exit 1
fi

cd $MY_HADOOP_HOME

if [ -z "$1" ]
then
	echo "usage: $0 <jobname>"
	exit 1
fi

if [ -z "USER_CMD" ]
then
	USER_CMD="sleep 3"
	echo WARN: running in test mode: command is: $USER_CMD
fi

if [ -z "$LOCAL_RESULTS_DIR" ]
then
	export LOCAL_RESULTS_DIR="/hadoop/results/my-log"
fi

if [ -z "$RES_SERVER" ]
then
	echo "$0: please export RES_SERVER (the server to collect the results to)"
	exit 1
fi

echoPrefix=`eval $ECHO_PATTERN`

local_dir=$1
collect_dir=$2
job=$3
logExports=$4
hdfsJobDir=$5
log=$local_dir/log_${LOG_PREFIX}.txt
liveProcesses=$local_dir/liveProcesses.txt

echo "$echoPrefix: sudo ssh $RES_SERVER mkdir -p $collect_dir"
if ! sudo ssh $RES_SERVER mkdir -p $collect_dir;then
	echo $0: error creating $collect_dir on $RES_SERVER
	exit 1
fi

echo "sudo ssh $RES_SERVER chown -R $USER $collect_dir"
sudo ssh $RES_SERVER chown -R $USER $collect_dir

echo LOG DIR IS: $collect_dir
echo "$echoPrefix: mkdir -p $local_dir"
if ! mkdir -p $local_dir;then
	echo $0: error creating $local_dir
	exit 1
fi

echo "HADOOP_CONF_DIR=$HADOOP_CONF_DIR" >> $log
echo "dir=$local_dir" >> $log
echo "collect_dir=$collect_dir" >> $log
echo "RES_SERVER=$RES_SERVER" >> $log
echo "job=$job" >> $log
echo "hostname: `hostname`" >> $log
echo "user command is: $USER_CMD" >> $log

#generate statistics

echo "$echoPrefix: sudo $EXEC_SLAVES  pkill -f dstat"
cat $HADOOP_CONF_DIR/slaves.sh
$EXEC_SLAVES  echo "test" > /tmp/1.txt
sudo $EXEC_SLAVES  pkill -f dstat
sleep 1

echo "$echoPrefix: generating statistics"
sudo $EXEC_SLAVES  if mkdir -p $local_dir\; then dstat -f --noheaders --output $local_dir/\`hostname\`.${DSTAT_LOCAL_FILE_NAME} \> $DEV_NULL_PATH\; else echo error in dstat\; exit 2\; fi &
sleep 2
sudo $EXEC_SLAVES chown -R $USER $local_dir

#run user command
echo -e \\n\\n
echo "$echoPrefix: running user command: $USER_CMD"
echo -e \\n\\n

### Cheking preReqs

preReqFlags=$PRE_REQ_TEST_FLAGS
if [[ "$preReqFlags" == "-" ]];then
	preReqFlags=$DEFAULT_PRE_REQ_TEST_FLAGS
fi

echo "$echoPrefix: checking pre-requests: bash $SCRIPTS_DIR/preReq.sh $preReqFlags"
bash $SCRIPTS_DIR/preReq.sh $preReqFlags
if (($? == $EEC3));then 
		echo "
		#!/bin/sh
		export TEST_STATUS=0
		export TEST_ERROR='$PRE_REQ_TEST_FAILURE_STRING'
		" > $logExports
	sudo chmod -R $DIRS_PERMISSIONS $local_dir
	echo logExports is: $logExports
	echo local_dir is: $local_dir
	echo collect_dir is: $collect_dir
	scp -r $local_dir/* $RES_SERVER:$collect_dir/
	exit $SEC
fi	

# here we actually run the main [MapReduce] job !!!
coresCountBefore=`ls $CORES_DIR | grep -c "core\."`
cmd_status=0
tstart=`date`
tStartSec=`date +"%s"`
passed=0
testOutput=$local_dir/testOutput.txt
####################

if (($TRACE_JOB_FLAG==0));then
	eval $USER_CMD 2>&1 | tee $testOutput
	retVal=$?
	echo "********** retVal is: $retVal **********"
	if (($retVal != 0)) && (($retVal != 126));then
		echo $echoPrefix: error user command "<$USER_CMD>" has failed
		cmd_status=3
	else
		passed=1
	fi
	#if ! eval $USER_CMD 2>&1 | tee $testOutput;then
	#	echo $echoPrefix: error user command "<$USER_CMD>" has failed
	#	cmd_status=3
	#else 
	#	passed=1
	#fi
else
	$USER_CMD 2>&1 | tee $testOutput &
	bash $SCRIPTS_DIR/isJobStillRunning.sh $testOutput
	isJobFinished=$?
	echo "$echoPrefix: risJobFinished status is $isJobFinished"
	if (( $isJobFinished != 8 ));then
		echo $echoPrefix: error user command "<$USER_CMD>" has failed
		cmd_status=3
	else 
		passed=1
	fi
fi
####################
#sudo bin/slaves.sh ${SCRIPTS_DIR}/cache_flush.sh
tEndBecWithoutFlush=`date +"%s"`
if (($CACHE_FLUHSING == 1));then
	sudo pdsh -w $RELEVANT_SLAVES_BY_COMMAS "sudo sync; echo 3 > /proc/sys/vm/drop_caches; echo 'syncronized' > $STATUS_DIR/syncValidation.txt"
fi
tEndBecWithFlush=`date +"%s"`
tend=`date`
echo "user command started at: $tstart" >> $log
echo "user command ended   at: $tend" >> $log
durationWithFlush=`echo "scale=1; $tEndBecWithFlush-$tStartSec" | bc`
durationWithoutFlush=`echo "scale=1; $tEndBecWithoutFlush-$tStartSec" | bc`
if (($CACHE_FLUHSING == 1));then
	duration=$durationWithFlush
else
	duration=$durationWithoutFlush	
fi
applicationId=`grep "$APPLICATION_ID_GREP_IDENTIFIER" $testOutput | awk '{print $7}'`
jobId=`grep "$JOB_ID_GREP_IDENTIFIER" $testOutput | awk '{print $7}'`
coresCountAfter=`ls $CORES_DIR | grep -c "core\."`
#echo WITH: $durationWithFlush, WITHOUT: $durationWithoutFlush

if [ `cat $testOutput | egrep -ic '("Job Failed"|exception)'` -ne 0 ];then 
	echo "$echoPrefix: ERROR - found error/fail/exception"
	cmd_status=4;
	if [ `cat $testOutput | egrep -ic "map 100% reduce 100%"` -eq 1 ];then 
		echo "Job has finished"
		#cmd_status=3
###############################################

	# important change - not leaving it like this without considering idan/avner
		cmd_status=0


###############################################
	fi
fi

echo "$echoPrefix: user command has terminated"
sleep 2
kill %1 #kill above slaves for terminating all dstat commands
sleep 1

$EXEC_SLAVES sudo pkill -f dstat

#cd -

if (( $cmd_status == 0 ));then
	echo "$echoPrefix: SUCCESS"
else
	#ssh $RES_SERVER "mv $collect_dir `cd $collect_dir/..; pwd`/${job}_ERROR"
	echo "$echoPrefix: mv $collect_dir ${collect_dir}_ERROR"
	sudo ssh $RES_SERVER "mv $collect_dir ${collect_dir}_ERROR"
	collect_dir=${collect_dir}_ERROR
fi

# producing history log
if [[ $PROGRAM != "pi" ]];then
	
	if (($YARN_HADOOP_FLAG == 1));then
		#bin/hadoop fs -ls /tmp/*/*/*/*/job_1378653723203_0002/*.jhist 
		historyPath=`$HADOOP_FS -ls $PATH_TO_JOB_INFO/$jobId/$RELATIVE_PATH_TO_JOB_HISTORY_ON_DFS | tail -n 1 | awk '{print $8}'`
		confPath=`$HADOOP_FS -ls $PATH_TO_JOB_INFO/$jobId/$RELATIVE_PATH_TO_JOB_CONF_ON_DFS | tail -n 1 | awk '{print $8}'`
	else
		historyPath=$hdfsJobDir
		confPath=$hdfsJobDir/$RELATIVE_PATH_TO_JOB_CONF_ON_DFS
	fi
	jobHistory=$local_dir/$JOB_HISTORY_FILE_NAME
	eval $JOB_OPTIONS -history $historyPath | tee $jobHistory
	eval $HADOOP_FS -copyToLocal $confPath $local_dir
	testSucceed=`grep -c "$JOB_HISTORY_SUCCESS_OUTPUT" $jobHistory`
fi

echo "COMMAND IS: pdsh -w $RELEVANT_MACHINES_BY_COMMAS \"ps -ef | grep java\"" > $liveProcesses
pdsh -w $RELEVANT_MACHINES_BY_COMMAS "ps -ef | grep java" >> $liveProcesses

liveAttemps=`pdsh -w $RELEVANT_MACHINES_BY_COMMAS "ps -ef | grep java" | grep "attempt"`
if [[ -n $liveAttemps ]];then
	echo "$echoPrefix: THERE ARE STILL LIVE ATTEMPS - $liveAttemps"
############## need to un-comment it when UDA will support cleanning processes after fallback ###########################################
	
	#testSucceed=0
	
#########################################################################################################################################
else
	echo "$echoPrefix: there are no live attemps"
fi

if [[ $PROGRAM == "terasort" ]] 
then
	
	teraval="-1" # -1 means that the user don't want to preform teravalidte
	inEqualOut="-1"
	if (( $TERAVALIDATE != 0 )) && (( $cmd_status != 4 ));then
		echo "$echoPrefix: Running TeraValidate"
		teravalidate="$EXEC_JOB $HADOOP_EXAMPLES_JAR_EXP teravalidate $TERASORT_DIR $TERAVAL_DIR"
		echo "$echoPrefix: $teravalidate"
		eval $teravalidate
		valll="eval $HADOOP_FS -ls $TERAVAL_DIR"
		eval $valll | tee $TMP_DIR/vallFile.txt
		if (($? == 0));then
			valSum=`cat $TMP_DIR/vallFile.txt | awk 'BEGIN { sum=0 }{ if ($8 ~ /part-/) { sum=sum+$5 }  } END {print sum}'`
		else
			valSum=1
		fi

		echo ""
		echo "$echoPrefix: val Sum is: $valSum"
	
		teraval=0
		if (($YARN_HADOOP_FLAG == 1)); then
			numOfOutputFiles=`cat $TMP_DIR/vallFile.txt | grep "part-" | wc -l` 
			if (( $numOfOutputFiles != 1 )); then
				valSum=1
			else
				
				teravalOutputFileName=`cat $TMP_DIR/vallFile.txt | grep "part-" | awk '{split($8,tmp,"/");print tmp[3]}'`
				teravalOutputFile=$TMP_DIR/$teravalOutputFileName				
				getFileCmd="$HADOOP_FS -copyToLocal $TERAVAL_DIR/$teravalOutputFileName $teravalOutputFile"
				eval $getFileCmd
				numOfLinesInOutputFile=`cat $teravalOutputFile | wc -l`
				echo "$echoPrefix: teravalOutputFileName=$teravalOutputFileName getFileCmd=$getFileCmd numOfLinesInOutputFile=$numOfLinesInOutputFile"
				if (( $numOfLinesInOutputFile != 1 )); then
					valSum=1
				else
					valSum=0
				fi
				sudo rm -rf $teravalOutputFile
			fi
		fi
		
		if (( $valSum == 0))
		then
			teraval=1
			echo "TERAVALIDATE SUCCEEDED" >> $log
			echo -e \\n\\n
			echo "$echoPrefix: TERAVALIDATE SUCCEEDED"
			echo -e \\n\\n
			sleep 4

			echo "$echoPrefix: Removing validate temp files"
			rm -rf $TMP_DIR/vallFile.txt

			echo "$echoPrefix: Removing $TERAVAL_DIR"
			eval $HADOOP_FS_RMR $TERAVAL_DIR
		else
			echo "TERAVALIDATE FAILED" >> $log
			echo -e \\n\\n
			echo "$echoPrefix: THIS IS BAD TERAVALIDATE FAILED!! "
			echo -e \\n\\n
			testSucceed=0
		fi

		inputdir="eval $HADOOP_FS -ls ${TEST_INPUT_DIR}" 
		eval $inputdir | tee $TMP_DIR/inputFile.txt
		inputSum=`cat $TMP_DIR/inputFile.txt | awk 'BEGIN { sum=0 }{ if ($8 ~ /part-/) { sum=sum+$5}  } END {print sum}'`

		echo "$echoPrefix: inputSum is: $inputSum"

		outputdir="eval $HADOOP_FS -ls $TERASORT_DIR"
		$outputdir | tee $TMP_DIR/outputFile.txt
		outputSum=`cat $TMP_DIR/outputFile.txt | awk 'BEGIN { sum=0 }{ if ($8 ~ /part-/) { sum=sum+$5}  } END {print sum}'`

		echo "$echoPrefix:  outputSum is: $outputSum"

		inEqualOut=0
		if (( $inputSum == $outputSum ))
		then
			inEqualOut=1
			echo "TERASORT OUTPUT==TERASORT INPUT -->SUCCEEDED" >> $log
			echo "$echoPrefix: GOOD! TERASORT OUTPUT = TERASORT INPUT"
			sleep 3
			echo "$echoPrefix: removing $TMP_DIR/inputFile.txt and $TMP_DIR/outputFile.txt"
			rm -rf $TMP_DIR/inputFile.txt
			rm -rf $TMP_DIR/outputFile.txt

		else
			echo "TERASORT OUTPUT!=TERASORT INPUT --> FAILED" >> $log
			echo "$echoPrefix: NOT GOOD! TERASORT OUTPUT and INPUT ARENT EQUAL, PLEASE CHECK!!"
		fi
	elif (( $cmd_status == 4 ));then
		echo "$echoPrefix: not running validate, test failed"
	fi
elif [[ $PROGRAM == "sort" ]];then
	echo "$echoPrefix: Running testmapredsort"
	testmapredsort="$EXEC_JOB $HADOOP_TEST_JAR_EXP testmapredsort -sortInput $TEST_INPUT_DIR -sortOutput $SORT_DIR"
	statusFile=$TMP_DIR/testmapredsortOutput.txt
	eval $testmapredsort | tee $statusFile
	if ((`grep -c "SUCCESS" $statusFile` == 0));then
		testSucceed=0
	fi
#&& (( $passed == 1 ))
elif [[ $PROGRAM == "wordcount" ]] 
then
	testOutputDir=$TMP_DIR_LOCAL_DISK/$job/udaOutput_`eval $CURRENT_DATE_PATTERN`
	mkdir -p $testOutputDir
	sudo rm -rf $testOutputDir/*
	echo "$echoPrefix: getting the job output files from the HDFS into $testOutputDir"
	eval $HADOOP_FS -copyToLocal $TEST_OUTPUT_DIR/part* $testOutputDir
	filesCount=`ls $testOutputDir | grep -c ""`
	
	if (($filesCount>0));then
		eval $HADOOP_FS_RMR $TEST_OUTPUT_DIR_VANILLA
		vanillaCmd="$USER_CMD_VANILLA -Dmapred.reduce.tasks=$filesCount $TEST_INPUT_DIR $TEST_OUTPUT_DIR_VANILLA"
		echo "$echoPrefix: running wordcount with vanilla: $vanillaCmd"
		vanillaCompareOutput=$local_dir/$job.txt
		if ! eval $vanillaCmd 2>&1 | tee $vanillaCompareOutput; then
			echo "$echoPrefix: error occured during running wordcount with vanilla "<$vanillaCmd>" for checking the wordcount-output"
			cmd_status=3
		fi

		vanillaOutputDir=$TMP_DIR_LOCAL_DISK/$job/vanillaOutput_`eval $CURRENT_DATE_PATTERN`
		mkdir -p $vanillaOutputDir
		eval $HADOOP_FS -copyToLocal $TEST_OUTPUT_DIR_VANILLA/part* $vanillaOutputDir
		status=`diff $testOutputDir $vanillaOutputDir`
		if [[ -z $status ]];then
			echo "$echoPrefix: output is correct"
			rm -rf $testOutputDir
			rm -rf $vanillaOutputDir
		else
			echo "$echoPrefix: mismatch has found between the wordcount test output and the wordcount vanilla output!"
			testSucceed=0
		fi
	else
		echo "$echoPrefix: wordcount failed - there are no output files"
		testSucceed=0
	fi
elif [[ $PROGRAM == "pi" ]];then
	piEstimation=`grep "Estimated value of Pi is" $testOutput | awk 'BEGIN{};{print $6}'`
	echo "pi estimation is $piEstimation"
	piDelta=`echo "scale=4; ${PI_REAL_VALUE}-${piEstimation}" | bc`
	piDelta=`echo "scale=4; sqrt(${piDelta}^2)" | bc` # avoiding negative numbers
	echo "delta pi is $piDelta"
	errorRate=`echo "${piDelta}>${PI_NUMERIC_ERROR}" | bc`
	if (($errorRate==0));then
		piSucceed=1
	else
		piSucceed=0
	fi
	testSucceed=$piSucceed
elif [[ $PROGRAM == testDFSIO ]] || [[ $PROGRAM == TestDFSIO ]];then
	getFiledDFSIO "TestDFSIO ----- : "
	testType=$getFiledDFSIO_retValue	
	getFiledDFSIO "Date & time: "
	dateAndTime=$getFiledDFSIO_retValue	
	getFiledDFSIO "Number of files: "
	numOfFiles=$getFiledDFSIO_retValue	
	getFiledDFSIO "Total MBytes processed: "
	totalMbProcessed=$getFiledDFSIO_retValue	
	getFiledDFSIO "Throughput mb/sec: "
	throughput=$getFiledDFSIO_retValue	
	getFiledDFSIO "Average IO rate mb/sec: "
	avgIoRate=$getFiledDFSIO_retValue	
	getFiledDFSIO "IO rate std deviation: "
	ioRateStdDev=$getFiledDFSIO_retValue
	getFiledDFSIO "Test exec time sec: "
	testExecTime=$getFiledDFSIO_retValue
fi

	# managing cores
echo -e \\n\\n
coresNames=""
coreActualCount=0
coresCounter=$((coresCountAfter-coresCountBefore))
if (($coresCounter > 0));then
	for machine in `hostname` $RELEVANT_SLAVES_BY_SPACES;do
		coresPerMachine=`ls -t $CORES_DIR | grep -m $coresCounter "" | grep -c $machine`
		coreActualCount=$((coreActualCount+coresPerMachine))
		coresNames="coresNames `ls -t $CORES_DIR | grep -m $coresCounter \"\" | grep $machine`"
	done
	if (($coreActualCount > 0));then
		echo "$echoPrefix: $coreActualCount cores where found"
		testSucceed=0
		############# TEMP for reproducing hs_err issue 1/5/13 ############
		cp -r /data3/ori/loca* /.autodirect/mtrswgwork/oriz/local_`eval $CURRENT_DATE_PATTERN`
	else
		echo "$echoPrefix: no cores where found"
	fi
	#cmd_status=$EEC1
elif (($coresCounter < 0));then
	echo "$echoPrefix: there are less cores files then in the beginnig of the test! probably someone delete cores manually during this test"
	testSucceed=0
else
	echo "$echoPrefix: no cores where found"
fi
################## DELETE THIS AFTER 14/4/2013!! ##################
#sudo rm -rf $CORES_DIR/*
###################################################################
echo -e \\n\\n

echo "
	#!/bin/sh
	export exlTEST_STATUS=$testSucceed
	export exAPP_ID=$applicationId
	export exlPI_ESTIMATION=$piEstimation
	export exlPI_SUCCEED=$piSucceed
	export exlDURATION_WITH_FLUSH=$durationWithFlush
	export exlDURATION_WITHOUT_FLUSH=$durationWithoutFlush
	export exlDURATION=$duration
	export exlTERAVAL=$teraval
	export exlIN_EQUAL_OUT=$inEqualOut
	export exlCORES=$coresCounter
	export exlWORDCOUNT_SUCCEED=$testSucceed
	export exlSORT_SUCCEED=$testSucceed
		# testDFSIO
	export exlTEST_TYPE='$testType'
	export exlDATA_AND_TIME='$dateAndTime'
	export exlNUM_OF_FILES='$numOfFiles'
	export exlTOTAL_MB_PROCESSED='$totalMbProcessed'
	export exlTHROUGHPUT='$throughput'
	export exlAVERAGE_IO_RATE='$avgIoRate'
	export exlIO_RATE_STD_DEV='$ioRateStdDev'
	export exlTEST_EXEC_TIME='$testExecTime'
" > $logExports

#collect the generated statistcs
echo "$echoPrefix: collecting statistics"

if [[ -n $coresNames ]];then
	echo $coresNames > $local_dir/cores.txt
fi

bash $SCRIPTS_DIR/logsCollector.sh $collect_dir $local_dir $applicationId

echo "$echoPrefix: checking if the test passed"
bash -x $SCRIPTS_DIR/testStatusAnalyzer.sh $collect_dir | tee $collect_dir/testAnalyzing.txt
#bash -x $SCRIPTS_DIR/testStatusAnalyzer.sh $collect_dir 2>&1 | tee $collect_dir/testAnalyzing.txt


#echo "$cmd_status is cmd_status"
echo "$echoPrefix: exiting"
exit $cmd_status
