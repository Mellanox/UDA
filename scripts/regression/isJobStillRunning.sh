#!/bin/bash

# while loop checks whether job logs (jobTracker) have been updated lately if they haven't ruturns cmd status of failure

testOutput=$1


flag=1
time1=`ls -l $MY_HADOOP_HOME/logs/hadoop-*-jobtracker-*.log`
echo $time1
#testOutput 
jobSucceeded=0
cmd_status=8
for i in `seq 1 $IS_JOb_STILL_RUNNING_FAILURE_TIMES`
do
	sleep $IS_JOb_STILL_RUNNING_SLEEP_TIME
		doneCount=`grep -c -e "done" -e "Job complete" $testOutput`
		if (( $doneCount > 0 ));then
			echo "Job has FInisheD! CoOl"
			jobSucceeded=1
			break
		fi
	time2=`ls -l $MY_HADOOP_HOME/logs/hadoop-*-jobtracker-*.log`
	if [[ $time1 == $time2 ]]
	then
		doneCount=`grep -c -e "done" -e "Job complete" $testOutput`
		if (( $doneCount > 0 ));then
			echo "Job has FInisheD! CoOl"
			jobSucceeded=1
			break
		else
			echo "time1: $time1"
		fi
	else 
		time1=$time2
		echo "good still running!"
	fi
done

if (( $jobSucceeded == 1 ))
then
	echo "good run,continue"
	exit 8
else 
	echo "need to kill some"
	echo "ERROR JOB STUCK I'M LEAVING" >> $testOutput
	exit 9
fi

