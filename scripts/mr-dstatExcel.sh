#!/bin/bash

# Written by Avner BenHanoch
# Date: 2011-04-14
# Modified by IdanWe on 2011-06-07
#	- collect the results by using scp and not by using NFS mounts


#export HADOOP_SLAVE_SLEEP=0.1

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
JOB=$1

if [ -z "USER_CMD" ]
then
	USER_CMD="sleep 3"
	echo WARN: running in test mode: command is: $USER_CMD
fi

if [ -z "$RES_LOGDIR" ]
then
	export RES_LOGDIR="/hadoop/results/my-log"
fi

if [ -z "$RES_SERVER" ]
then
	echo "$0: please export RES_SERVER (the server to collect the results to)"
	exit 1
fi

local_dir=/tmp/$JOB
collect_dir=$RES_LOGDIR/$JOB
log=$local_dir/log.txt

export OUTDIR=$collect_dir

echo "$0: sudo ssh $RES_SERVER mkdir -p $collect_dir"
if ! sudo ssh $RES_SERVER mkdir -p $collect_dir
then
	echo $0: error creating $collect_dir on $RES_SERVER
	exit 1
fi

echo "$0:  mkdir -p $local_dir"
if ! mkdir -p $local_dir
then
	echo $0: error creating $local_dir
	exit 1
fi


#generate statistics
echo $0: generating statistcs
sudo $SLAVES  pkill -f dstat
sleep 1
sudo $SLAVES  if mkdir -p $local_dir\; then dstat -t -c -C total -d -D total -n -N total -m --noheaders --output $local_dir/\`hostname\`.dstat.csv \> /dev/null\; else echo error in dstat\; exit 2\; fi &
sleep 2

#run user command
echo $0: running user command: $USER_CMD
echo $0: running user command: $USER_CMD

echo "HADOOP_CONF_DIR=$HADOOP_CONF_DIR" >> $log

echo "dir=$local_dir" >> $log
echo "collect_dir=$collect_dir" >> $log
echo "RES_SERVER=$RES_SERVER" >> $log
echo "JOB=$JOB" >> $log


echo "hostname: `hostname`" >> $log
echo "user command is: $USER_CMD" >> $log

tstart=`date`
echo "user command started at: $tstart" >> $log

# here we actually run the main [MapReduce] job !!!
cmd_status=0
if ! eval $USER_CMD 2>&1 | tee $local_dir/$JOB.txt
then
	echo $0: error user command "<$USER_CMD>" has failed
	cmd_status=3
	passed=0
else 
	passed=1
fi


if [ `cat $local_dir/$JOB.txt | egrep -ic '(error|fail|exception)'` -ne 0 ]
then 
	echo "$(basename $0): ERROR - found error/fail/exception"
	cmd_status=4;
fi

tend=`date`
echo $0: user command has terminated
sleep 2
kill %1 #kill above slaves for terminating all dstat commands
sleep 1

$SLAVES sudo pkill -f dstat
#collect the generated statistcs
echo $0: collecting statistics

echo "user command ended   at: $tend" >> $log


sudo ssh $RES_SERVER mkdir -p $collect_dir/master-`hostname`/
sudo scp  -r $MY_HADOOP_HOME/logs/* $RES_SERVER:$collect_dir/master-`hostname`/
sudo scp  -r $local_dir/* $RES_SERVER:$collect_dir/

sudo $SLAVES ssh $RES_SERVER mkdir -p $collect_dir/slave-\`hostname\`/
sudo $SLAVES scp -r $MY_HADOOP_HOME/logs/\* $RES_SERVER:$collect_dir/slave-\`hostname\`/
sudo $SLAVES scp -r $local_dir/\* $RES_SERVER:$collect_dir/

echo $0: finished collecting statistics

#ls -lh --full-time $collect > /dev/null # workaround - prevent "tar: file changed as we read it"

#combine all the node's dstat to one file at cluster level
sudo ssh $RES_SERVER cat $collect_dir/\*.dstat.csv \| sort \| ${SCRIPTS_DIR}/reduce-dstat.awk \> $collect_dir/dstat-$JOB-cluster.csv

echo collecting hadoop master conf dir
echo sudo scp -r $HADOOP_CONF_DIR $RES_SERVER:$collect_dir/$(basename $HADOOP_CONF_DIR)
sudo scp -r $HADOOP_CONF_DIR $RES_SERVER:$collect_dir/$(basename $HADOOP_CONF_DIR)

#if ! tar zcf $collect.tgz $collect 2> /dev/null
#then
#	echo $0: error creating tgz file. Please, Try manually: tar zcf $collect.tgz $collect
#	exit 5
#fi

cd -

if (( $cmd_status != 0 ))
then
	#echo $0: SUCCESS, collected output is in $collect.tgz
	echo $0: SUCCESS
#	echo $0: "cmd_status is: $cmd_status"

else
	sudo ssh $RES_SERVER mv "$collect_dir" "ERROR_${collect_dir}"
fi


if (( $passed == 1 ))
then
	teravalidate="$MY_HADOOP_HOME/bin/hadoop jar hadoop*-examples*.jar teravalidate /terasort/output /validate/out"

	if (( $TERAVALIIDATE != 0 ))
	then
		echo "Running TeraValidate!!"
		echo "Running TeraValidate!!"
		echo "$teravalidate"

		$teravalidate

		valll="bin/hadoop fs -ls /validate/out"
		$valll | tee /tmp/vallFile.txt

		valSum=`cat /tmp/vallFile.txt | awk 'BEGIN { sum=0 }{ if ($8 ~ /part-/) { sum=sum+$5 }  } END {print sum}'`

		echo ""
		echo "val Sum is: $valSum"

		if (( $valSum == 0))
		then
			echo ""; echo ""; echo ""; echo ""; echo ""; echo ""; echo "";
			echo "TERAVALIDATE SUCCEEDED!! WO HU!!"
			echo "TERAVALIDATE SUCCEEDED!! WO HU!!"
			echo "TERAVALIDATE SUCCEEDED!! WO HU!!"
			echo "TERAVALIDATE SUCCEEDED!! WO HU!!"
			sleep 4

			echo "Removing validate tmp files"
			rm -rf /tmp/vallFile.txt

			echo "Removing /validate/out"
			echo "bin/hadoop fs -rmr /validate/out"
			bin/hadoop fs -rmr /validate/out
		else
			echo "THIS IS BAD TERAVALIDATE FAILED!! "
			exit 500 
		fi

		inputdir="bin/hadoop fs -ls ${INPUTDIR}" 
		$inputdir | tee /tmp/inputFile.txt
		inputSum=`cat /tmp/inputFile.txt | awk 'BEGIN { sum=0 }{ if ($8 ~ /part-/) { sum=sum+$5}  } END {print sum}'`

		echo "inputSum is: $inputSum"
		echo "inputSum is: $inputSum"

		outputdir="bin/hadoop fs -ls /terasort/output"
		$outputdir | tee /tmp/outputFile.txt
		outputSum=`cat /tmp/outputFile.txt | awk 'BEGIN { sum=0 }{ if ($8 ~ /part-/) { sum=sum+$5}  } END {print sum}'`

		echo "outputSum is: $outputSum"
		echo "outputSum is: $outputSum"

		if (( $inputSum == $outputSum ))
		then
			echo "GOOD! TERASORT OUTPUT = TERASORT INPUT"
			echo "GOOD! TERASORT OUTPUT = TERASORT INPUT"
			echo "GOOD! TERASORT OUTPUT = TERASORT INPUT"
			echo "GOOD! TERASORT OUTPUT = TERASORT INPUT"
			sleep 3
			echo "removing /tmp/inputFile.txt and /tmp/outputFile.txt"
			rm -rf /tmp/inputFile.txt
			rm -rf /tmp/outputFile.txt
 
		else
			echo "NOT GOOD! TERASORT OUTPUT and INPUT ARENT EQUAL, PLEASE CHECK!!"
		fi

	fi

fi

#echo "$cmd_status is cmd_status"

exit $cmd_status


