#!/bin/bash

# while loop checks whether job logs (jobTracker) have been updated lately if they haven't ruturns cmd status of failure

testOutput=$1

flag=1
time1=`ls -l $MY_HADOOP_HOME/logs/hadoop-*-jobtracker-*.log`
echo $time1
#testOutput 

while (( $flag==1 ));
do
	sleep 100
	time2=`ls -l $MY_HADOOP_HOME/logs/hadoop-*-jobtracker-*.log`
	if [[ $time1 == $time2 ]]
		then
		grep "done" $testOutput
		if (( $? == 0 ))
		then
			echo "Job has FInisheD! CoOl"
			cmd_status=8
		else
			echo "time1: $time1"
			echo "This IS Bad MaN!"
			cmd_status=6
		fi
		flag=2
	else 
		time1=$time2
		echo "good still running!"
	fi
done

if (( $cmd_status == 8 ))
then
	echo "good run,continue"
	exit 8
else 
	echo "need to kill some"
	echo "ERROR JOB STUCK I'M LEAVING" >> $testOutput
	exit 9
fi

