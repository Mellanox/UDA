#!/bin/bash

# Written by Avner BenHanoch
# Date: 2011-04-14
# Modified by IdanWe on 2011-06-07
#	- collect the results by using scp and not by using NFS mounts

if [ -z "$MY_HADOOP_HOME" ]
then
	echo "please export MY_HADOOP_HOME"
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
	echo "please export USER_CMD"
	exit 1
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

if [ -z "$SCRIPTS_DIR" ]
then
	echo "please export SCRIPTS_DIR (the location of our scripts on $RES_SERVER)"
	exit 1
fi

local_dir=/tmp/$JOB
collect_dir=$RES_LOGDIR/$JOB
log=$local_dir/log.txt

export OUTDIR=$collect_dir

echo "$0: ssh $RES_SERVER mkdir -p $collect_dir"
if ! ssh $RES_SERVER mkdir -p $collect_dir
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
$SLAVES  pkill -f dstat
sleep 1
$SLAVES  if mkdir -p $local_dir\; then dstat -t -c -C total -d -D total -n -N total -m --noheaders --output $local_dir/\`hostname\`.dstat.csv \> /dev/null\; else echo error in dstat\; exit 2\; fi &
sleep 2

#run user command
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

$SLAVES pkill -f dstat
#collect the generated statistcs
echo $0: collecting statistics

echo "user command ended   at: $tend" >> $log

JOB2="${JOB}_h"

echo "$MY_HADOOP_HOME/bin/hadoop job -history /terasort/output | tee $local_dir/$JOB2.txt"
$MY_HADOOP_HOME/bin/hadoop job -history /terasort/output | tee $local_dir/$JOB2.txt



ssh $RES_SERVER mkdir -p $collect_dir/master-`hostname`/
scp  -r $MY_HADOOP_HOME/logs/* $RES_SERVER:$collect_dir/master-`hostname`/
scp  -r $local_dir/* $RES_SERVER:$collect_dir/

$SLAVES ssh $RES_SERVER mkdir -p $collect_dir/slave-\`hostname\`/
$SLAVES scp -r $MY_HADOOP_HOME/logs/\* $RES_SERVER:$collect_dir/slave-\`hostname\`/
$SLAVES scp -r $local_dir/\* $RES_SERVER:$collect_dir/

echo $0: finished collecting statistics

#ls -lh --full-time $collect > /dev/null # workaround - prevent "tar: file changed as we read it"

#combine all the node's dstat to one file at cluster level
ssh $RES_SERVER cat $collect_dir/\*.dstat.csv \| sort \| ${SCRIPTS_DIR}/reduce-dstat.awk \> $collect_dir/dstat-$JOB-cluster.csv

echo collecting hadoop master conf dir
echo scp -r $HADOOP_CONF_DIR $RES_SERVER:$collect_dir/$(basename $HADOOP_CONF_DIR)
scp -r $HADOOP_CONF_DIR $RES_SERVER:$collect_dir/$(basename $HADOOP_CONF_DIR)

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
else
	ssh $RES_SERVER mv "$collect_dir" "ERROR_${collect_dir}"
fi

exit $cmd_status


