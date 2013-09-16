#!/bin/bash

# while loop checks whether job logs (jobTracker) have been updated lately if they haven't ruturns cmd status of failure
jobSuccessMacro()
{
	echo "$echoPrefix: job has finished successfuly"
	jobSucceeded=1
	break
}

echoPrefix=`eval $ECHO_PATTERN`	

testOutput=$1


flag=1
time1=`ls -l $MY_HADOOP_HOME/$JOB_LOG_PATH`
echo "$echoPrefix: time1 is $time1"
#testOutput 
jobSucceeded=0
cmd_status=8
for i in `seq 1 $IS_JOb_STILL_RUNNING_FAILURE_TIMES`
do
	sleep $IS_JOb_STILL_RUNNING_SLEEP_TIME
		doneCount=`grep -c -e "done" -e "Job complete" $testOutput`
		if (( $doneCount > 0 ));then
			jobSuccessMacro
		fi
	time2=`ls -l $MY_HADOOP_HOME/$JOB_LOG_PATH`
	if [[ $time1 == $time2 ]]
	then
		doneCount=`grep -c -e "done" -e "Job complete" $testOutput`
		if (( $doneCount > 0 ));then
			jobSuccessMacro
		else
			echo "$echoPrefix: time1 is $time1"
		fi
	else 
		time1=$time2
		echo "$echoPrefix: the job is still running"
	fi
done

if (( $jobSucceeded == 1 ));then
	exit 8
else 
	echo "$echoPrefix: the job dad stuch - killing it" >> $testOutput
	exit 9
fi

