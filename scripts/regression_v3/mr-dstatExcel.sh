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
SLAVES=$MY_HADOOP_HOME/bin/slaves.sh

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

echoPrefix=$(basename $0)

local_dir=$1
collect_dir=$2
job=$3
logExports=$4
hdfsJobDir=$5
log=$local_dir/log_${LOG_PREFIX}.txt


echo "$echoPrefix: sudo ssh $RES_SERVER mkdir -p $collect_dir"
if ! sudo ssh $RES_SERVER mkdir -p $collect_dir;then
	echo $0: error creating $collect_dir on $RES_SERVER
	exit 1
fi
sudo ssh $RES_SERVER chown -R $USER $collect_dir

echo LOG DIR IS: $collect_dir
echo "$echoPrefix: mkdir -p $local_dir"
if ! mkdir -p $local_dir;then
	echo $0: error creating $local_dir
	exit 1
fi

#generate statistics
echo "$echoPrefix: generating statistcs"
sudo $SLAVES  pkill -f dstat
sleep 1
sudo $SLAVES  if mkdir -p $local_dir\; then dstat -t -c -C total -d -D total -n -N total -m --noheaders --output $local_dir/\`hostname\`.dstat.csv \> /dev/null\; else echo error in dstat\; exit 2\; fi &
sleep 2
sudo $SLAVES chown -R $USER $local_dir

#run user command
echo -e \\n\\n
echo "$echoPrefix: running user command: $USER_CMD"
echo -e \\n\\n

echo "HADOOP_CONF_DIR=$HADOOP_CONF_DIR" >> $log
echo "dir=$local_dir" >> $log
echo "collect_dir=$collect_dir" >> $log
echo "RES_SERVER=$RES_SERVER" >> $log
echo "job=$job" >> $log
echo "hostname: `hostname`" >> $log
echo "user command is: $USER_CMD" >> $log


# here we actually run the main [MapReduce] job !!!
coresCountBefore=`ls $CORES_DIR | grep -c "core\."`
cmd_status=0
tstart=`date`
tStartSec=`date +"%s"`
passed=0
testOutput=$local_dir/$job.txt
####################
if (($TRACE_JOB_FLAG==0));then
	if ! eval $USER_CMD 2>&1 | tee $testOutput;then
		echo $echoPrefix: error user command "<$USER_CMD>" has failed
		cmd_status=3
	else 
		passed=1
	fi
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
sudo pdsh -w $RELEVANT_SLAVES_BY_COMMAS "sudo sync; echo 3 > /proc/sys/vm/drop_caches; echo 'syncronized' > $STATUS_DIR/syncValidation.txt"
tEndBecWithFlush=`date +"%s"`
tend=`date`
echo "user command started at: $tstart" >> $log
echo "user command ended   at: $tend" >> $log
durationWithFlush=`echo "scale=1; $tEndBecWithFlush-$tStartSec" | bc`
durationWithoutFlush=`echo "scale=1; $tEndBecWithoutFlush-$tStartSec" | bc`

coresCountAfter=`ls $CORES_DIR | grep -c "core\."`
#echo WITH: $durationWithFlush, WITHOUT: $durationWithoutFlush

if [ `cat $testOutput | egrep -ic '(error|fail|exception)'` -ne 0 ];then 
	echo "$echoPrefix: ERROR - found error/fail/exception"
	cmd_status=4;
	if [ `cat $testOutput | egrep -ic "map 100% reduce 100%"` -eq 1 ];then 
		echo "Job has finished"
		cmd_status=3
	fi
fi

echo "$echoPrefix: user command has terminated"
sleep 2
kill %1 #kill above slaves for terminating all dstat commands
sleep 1

$SLAVES sudo pkill -f dstat

#cd -

if (( $cmd_status == 0 ));then
	echo "$echoPrefix: SUCCESS"
else
	#ssh $RES_SERVER "mv $collect_dir `cd $collect_dir/..; pwd`/${job}_ERROR"
	echo "$echoPrefix: mv $collect_dir ${collect_dir}_ERROR"
	sudo ssh $RES_SERVER "mv $collect_dir ${collect_dir}_ERROR"
	collect_dir=${collect_dir}_ERROR
fi

teraval="-1" # -1 means that the user don't want to preform teravalidte
inEqualOut="-1"
if [[ $PROGRAM == "terasort" ]] && (( $passed == 1 )) && (( $TERAVALIDATE != 0 ))
then
	if (( $cmd_status == 4 ));then
		echo "$echoPrefix: not running validate, test failed"
	else
		echo "$echoPrefix: Running TeraValidate"
		teravalidate="${MY_HADOOP_HOME}/bin/hadoop jar hadoop*-examples*.jar teravalidate $TERASORT_DIR $TERAVAL_DIR"
		echo "$echoPrefix: $teravalidate"
		eval $teravalidate
		valll="${MY_HADOOP_HOME}/bin/hadoop fs -ls $TERAVAL_DIR"
		eval $valll | tee $TMP_DIR/vallFile.txt

		valSum=`cat $TMP_DIR/vallFile.txt | awk 'BEGIN { sum=0 }{ if ($8 ~ /part-/) { sum=sum+$5 }  } END {print sum}'`

		echo ""
		echo "$echoPrefix: val Sum is: $valSum"
	
		teraval=0
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
			echo "$echoPrefix: bin/hadoop fs -rmr $TERAVAL_DIR"
			bin/hadoop fs -rmr $TERAVAL_DIR
		else
			echo "TERAVALIDATE FAILED" >> $log
			echo -e \\n\\n
			echo "$echoPrefix: THIS IS BAD TERAVALIDATE FAILED!! "
			echo -e \\n\\n
			exit 500 
		fi

		inputdir="bin/hadoop fs -ls ${TEST_INPUT_DIR}" 
		eval $inputdir | tee $TMP_DIR/inputFile.txt
		inputSum=`cat $TMP_DIR/inputFile.txt | awk 'BEGIN { sum=0 }{ if ($8 ~ /part-/) { sum=sum+$5}  } END {print sum}'`

		echo "$echoPrefix: inputSum is: $inputSum"

		outputdir="bin/hadoop fs -ls $TERASORT_DIR"
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
	fi
elif [[ $PROGRAM == "sort" ]];then
	echo "$echoPrefix: Running testmapredsort"
	testmapredsort="${MY_HADOOP_HOME}/bin/hadoop jar hadoop-*test*.jar testmapredsort -sortInput $TEST_INPUT_DIR -sortOutput $SORT_DIR"
	statusFile=$TMP_DIR/testmapredsortOutput.txt
	eval $testmapredsort | tee $statusFile
	testmapredsortSuccess=0
	if ((`grep -c "SUCCESS" $statusFile` == 1));then
		testmapredsortSuccess=1
	fi
elif [[ $PROGRAM == "wordcount" ]] && (( $passed == 1 ))
then
	tempDir=$TMP_DIR_LOCAL_DISK/$job
	testOutputDir=$tempDir/testOutput
	mkdir -p $testOutputDir
	echo $echoPrefix: getting the job output files from the HDFS into $testOutputDir
	${MY_HADOOP_HOME}/bin/hadoop fs -copyToLocal $TEST_OUTPUT_DIR/part* $testOutputDir
	filesCount=`ls $testOutputDir | grep -c ""`
	
	vanillaCmd="$USER_CMD_VANILLA -Dmapred.reduce.tasks=$filesCount $TEST_INPUT_DIR $TEST_OUTPUT_DIR_VANILLA"
	echo $echoPrefix: running wordcount with vanilla: $vanillaCmd
	vanillaCompareOutput=$local_dir/$job.txt
	if ! eval $vanillaCmd 2>&1 | tee $vanillaCompareOutput; then
		echo $echoPrefix: error occured during running wordcount with vanilla "<$vanillaCmd>" for checking the wordcount-output
		cmd_status=3
	fi

	vanillaOutputDir=$tempDir/vanillaOutput
	mkdir -p $vanillaOutputDir
	${MY_HADOOP_HOME}/bin/hadoop fs -copyToLocal $TEST_OUTPUT_DIR_VANILLA/part* $vanillaOutputDir
	status=`diff $testOutputDir $vanillaOutputDir`
	if [[ -z $status ]];then
		echo $echoPrefix: output is correct
		#rm -rf $testOutputDir
		#rm -rf $vanillaOutputDir
		wordcountSucceed=1
	else
		echo $echoPrefix: mismatch has found between the wordcount test output and the wordcount vanilla output!
		wordcountSucceed=0
	fi
	bin/hadoop fs -rmr $TEST_OUTPUT_DIR_VANILLA
elif [[ $PROGRAM == "pi" ]];then
	piEstimation=`grep "Estimated value of Pi is" $testOutput | awk 'BEGIN{};{print $6}'`
	echo "pi estimation is " $piEstimation
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
coresCounter=$((coresCountAfter-coresCountBefore))
if (($coresCounter > 0));then
	coresNames=`ls -t $CORES_DIR | grep -m $coresCounter "core"`
	echo "$echoPrefix: cores where found: $coresNames"
	#cmd_status=$EEC1
elif (($coresCounter < 0));then
	echo "$echoPrefix: there are less cores files then in the beginnig of the test! probably someone delete cores manually during this test"
else
	echo "$echoPrefix: no cores where found"
fi
echo -e \\n\\n

echo "
	#!/bin/sh
	export exlPI_ESTIMATION=$piEstimation
	export exlDURATION_WITH_FLUSH=$durationWithFlush
	export exlDURATION_WITHOUT_FLUSH=$durationWithoutFlush
	export exlTERAVAL=$teraval
	export exlIN_EQUAL_OUT=$inEqualOut
	export exlCORES=$coresCounter
	export exlWORDCOUNT_SUCCEED=$wordcountSucceed
	export exlSORT_SUCCEED=$testmapredsortSuccess
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

if [[ $PROGRAM != "pi" ]];then
	readbleHistory="${job}_h"
	fullConf=$TMP_DIR/configuration-Full.txt
	$MY_HADOOP_HOME/bin/hadoop job -history $hdfsJobDir | tee $local_dir/$readbleHistory.txt
	$MY_HADOOP_HOME/bin/hadoop fs -cat $hdfsJobDir/_logs/history/*conf.xml > $fullConf
fi

if [[ -n $coresNames ]];then
	echo $coresNames > $local_dir/cores.txt
fi

ssh $RES_SERVER mkdir -p $collect_dir/master-`hostname`/
#ssh $RES_SERVER chown -R $USER  $collect_dir/master-`hostname`/
scp -r $MY_HADOOP_HOME/logs/* $RES_SERVER:$collect_dir/master-`hostname`/
scp -r $local_dir/* $RES_SERVER:$collect_dir/
scp $fullConf $RES_SERVER:$collect_dir/

$SLAVES ssh $RES_SERVER mkdir -p $collect_dir/slave-\`hostname\`/
#$SLAVES chown -R $USER  $collect_dir/slave-\`hostname\`/
$SLAVES scp -r $MY_HADOOP_HOME/logs/\* $RES_SERVER:$collect_dir/slave-\`hostname\`/
$SLAVES scp -r $local_dir/\* $RES_SERVER:$collect_dir/

sudo ssh $RES_SERVER chown -R $USER $collect_dir

echo "$echoPrefix: finished collecting statistics"

#ls -lh --full-time $collect > /dev/null # workaround - prevent "tar: file changed as we read it"

#combine all the node's dstat to one file at cluster level
ssh $RES_SERVER cat $collect_dir/\*.dstat.csv \| sort \| $SCRIPTS_DIR/reduce-dstat.awk \> $collect_dir/dstat-$job-cluster.csv

echo "$echoPrefix: collecting hadoop master conf dir"
echo "$echoPrefix: scp -r $HADOOP_CONF_DIR $RES_SERVER:$collect_dir/$(basename $HADOOP_CONF_DIR) > /dev/null"
scp -r $HADOOP_CONF_DIR $RES_SERVER:$collect_dir/$(basename $HADOOP_CONF_DIR) > /dev/null

#if ! tar zcf $collect.tgz $collect 2> /dev/null
#then
#	echo $0: error creating tgz file. Please, Try manually: tar zcf $collect.tgz $collect
#	exit 5
#fi

#echo "$cmd_status is cmd_status"
echo "$echoPrefix: exiting"
exit $cmd_status