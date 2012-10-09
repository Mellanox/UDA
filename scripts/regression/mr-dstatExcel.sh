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

#logFolder=$1
#local_dir=$TMP_DIR/$JOB
#collect_dir=$logFolder/$JOB
#log=$local_dir/log.txt

local_dir=$1
collect_dir=$2
JOB=$3
logExports=$4
log=$local_dir/log.txt

export OUTDIR=$collect_dir
echo "$0: sudo ssh $RES_SERVER mkdir -p $collect_dir"
if ! sudo ssh $RES_SERVER mkdir -p $collect_dir;then
	echo $0: error creating $collect_dir on $RES_SERVER
	exit 1
fi
sudo ssh $RES_SERVER chown -R $USER $collect_dir

echo LOG DIR IS: $collect_dir
echo "$0:  mkdir -p $local_dir"
if ! mkdir -p $local_dir;then
	echo $0: error creating $local_dir
	exit 1
fi

#generate statistics
echo $0: generating statistcs
sudo $SLAVES  pkill -f dstat
sleep 1
sudo $SLAVES  if mkdir -p $local_dir\; then dstat -t -c -C total -d -D total -n -N total -m --noheaders --output $local_dir/\`hostname\`.dstat.csv \> /dev/null\; else echo error in dstat\; exit 2\; fi &
sleep 2
sudo $SLAVES chown -R $USER $local_dir

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
#tstart=`date`
echo "user command started at: $tstart" >> $log

# here we actually run the main [MapReduce] job !!!
coresCountBefore=`ls $CORES_DIR | grep -c "core\."`
cmd_status=0
tstart=`date`
tStartSec=`date +"%s"`
passed=0
if ! eval $USER_CMD 2>&1 | tee $local_dir/$JOB.txt
then
	echo $0: error user command "<$USER_CMD>" has failed
	cmd_status=3
else 
	passed=1
fi
#sudo bin/slaves.sh ${SCRIPTS_DIR}/cache_flush.sh
tEndBecWithoutFlush=`date +"%s"`
sudo pdsh -w $csvSLAVES "sudo sync; echo 3 > /proc/sys/vm/drop_caches; echo 'syncronized' > $TMP_DIR/syncValidation.txt"
tEndBecWithFlush=`date +"%s"`
tend=`date`
echo "user command ended   at: $tend" >> $log
durationWithFlush=`echo "scale=1; $tEndBecWithFlush-$tStartSec" | bc`
durationWithoutFlush=`echo "scale=1; $tEndBecWithoutFlush-$tStartSec" | bc`

coresCountAfter=`ls $CORES_DIR | grep -c "core\."`
#echo WITH: $durationWithFlush, WITHOUT: $durationWithoutFlush

if [ `cat $local_dir/$JOB.txt | egrep -ic '(error|fail|exception)'` -ne 0 ];then 
	echo "$(basename $0): ERROR - found error/fail/exception"
	cmd_status=4;
fi

echo $0: user command has terminated
sleep 2
kill %1 #kill above slaves for terminating all dstat commands
sleep 1

$SLAVES sudo pkill -f dstat

#cd -

if (( $cmd_status == 0 ));then
	#echo $0: SUCCESS, collected output is in $collect.tgz
	echo $0: SUCCESS
#	echo $0: "cmd_status is: $cmd_status"
else
	#ssh $RES_SERVER "mv $collect_dir `cd $collect_dir/..; pwd`/${JOB}_ERROR"
	echo $0: mv $collect_dir ${collect_dir}_ERROR
	sudo ssh $RES_SERVER "mv $collect_dir ${collect_dir}_ERROR"
	collect_dir=${collect_dir}_ERROR
fi
#tmp=`cd collect_dir/..; pwd`
#echo TMP IS: $tmp 

teraval="-1" # -1 means that the user don't want to preform teravalidte
inEqualOut="-1"
if (( $passed == 1 )) && (( $TERAVALIDATE != 0 ))
then
	echo "Running TeraValidate!!"
	echo "Running TeraValidate!!"
	echo "$teravalidate"
	teravalidate="${MY_HADOOP_HOME}/bin/hadoop jar hadoop*-examples*.jar teravalidate /terasort/output /validate/out"
	eval $teravalidate
	valll="${MY_HADOOP_HOME}/bin/hadoop fs -ls /validate/out"
	eval $valll | tee $TMP_DIR/vallFile.txt

	valSum=`cat $TMP_DIR/vallFile.txt | awk 'BEGIN { sum=0 }{ if ($8 ~ /part-/) { sum=sum+$5 }  } END {print sum}'`

	echo ""
	echo "val Sum is: $valSum"
	
	teraval=0
	if (( $valSum == 0))
	then
		teraval=1
		echo "TERAVALIDATE SUCCEEDED" >> $log
		echo ""; echo ""; echo ""; echo ""; echo ""; echo ""; echo "";
		echo "TERAVALIDATE SUCCEEDED!! WO HU!!"
		echo "TERAVALIDATE SUCCEEDED!! WO HU!!"
		echo "TERAVALIDATE SUCCEEDED!! WO HU!!"
		echo "TERAVALIDATE SUCCEEDED!! WO HU!!"
		sleep 4

		echo "Removing validate temp files"
		rm -rf $TMP_DIR/vallFile.txt

		echo "Removing /validate/out"
		echo "bin/hadoop fs -rmr /validate/out"
		bin/hadoop fs -rmr /validate/out
	else
		echo "TERAVALIDATE FAILED" >> $log
		echo "THIS IS BAD TERAVALIDATE FAILED!! "
		exit 500 
	fi

	inputdir="bin/hadoop fs -ls ${INPUTDIR}" 
	$inputdir | tee $TMP_DIR/inputFile.txt
	inputSum=`cat $TMP_DIR/inputFile.txt | awk 'BEGIN { sum=0 }{ if ($8 ~ /part-/) { sum=sum+$5}  } END {print sum}'`

	echo "inputSum is: $inputSum"
	echo "inputSum is: $inputSum"

	outputdir="bin/hadoop fs -ls /terasort/output"
	$outputdir | tee $TMP_DIR/outputFile.txt
	outputSum=`cat $TMP_DIR/outputFile.txt | awk 'BEGIN { sum=0 }{ if ($8 ~ /part-/) { sum=sum+$5}  } END {print sum}'`

	echo "outputSum is: $outputSum"
	echo "outputSum is: $outputSum"

	inEqualOut=0
	if (( $inputSum == $outputSum ))
	then
		inEqualOut=1
		echo "TERASORT OUTPUT==TERASORT INPUT -->SUCCEEDED" >> $log
		echo "GOOD! TERASORT OUTPUT = TERASORT INPUT"
		echo "GOOD! TERASORT OUTPUT = TERASORT INPUT"
		echo "GOOD! TERASORT OUTPUT = TERASORT INPUT"
		echo "GOOD! TERASORT OUTPUT = TERASORT INPUT"
		sleep 3
		echo "removing $TMP_DIR/inputFile.txt and $TMP_DIR/outputFile.txt"
		rm -rf $TMP_DIR/inputFile.txt
		rm -rf $TMP_DIR/outputFile.txt

	else
		echo "TERASORT OUTPUT==TERASORT INPUT --> FAILED" >> $log
		echo "NOT GOOD! TERASORT OUTPUT and INPUT ARENT EQUAL, PLEASE CHECK!!"
	fi
fi

	# managing cores
echo -e \\n\\n
coresNames=""
coresCounter=$((coresCountAfter-coresCountBefore))
if (($coresCounter > 0));then
	coresNames=`ls -t $CORES_DIR | grep -m $coresCounter "core"`
	echo "cores where found:"
	echo "$coresNames"	
	cmd_status=$EEC1
elif (($coresCounter < 0));then
	echo "$0: there are less cores files then in the beginnig of the test! probably someone delete cores manually during this test"
else
	echo "no cores where found"
fi
echo -e \\n\\n

echo "
	export exlDURATION_WITH_FLUSH=$durationWithFlush
	export exlDURATION_WITHOUT_FLUSH=$durationWithoutFlush
	export exlTERAVAL=$teraval
	export exlIN_EQUAL_OUT=$inEqualOut
	export exlCORES=$coresCounter
" >> $logExports

#collect the generated statistcs
echo $0: collecting statistics

readbleHistory="${JOB}_h"
#crudeHistory="${JOB}_crudeHistory"

echo "$MY_HADOOP_HOME/bin/hadoop job -history /terasort/output | tee $local_dir/$readbleHistory.txt"
$MY_HADOOP_HOME/bin/hadoop job -history /terasort/output | tee $local_dir/$readbleHistory.txt
echo "$MY_HADOOP_HOME/bin/hadoop job -can /terasort/output | tee $local_dir/$readbleHistory.txt"
#sudo mkdir $TMP_DIR/historyAndConf
#$MY_HADOOP_HOME/bin/hadoop job -cat /terasort/output/_logs/history/*TeraSort > /$TMP_DIR/historyAndConf/a.txt
fullConf=$TMP_DIR/configuration-Full.txt
$MY_HADOOP_HOME/bin/hadoop fs -cat /terasort/output/_logs/history/*conf.xml > $fullConf
#crudeHistory=/$TMP_DIR/historyAndConf/`ls /$TMP_DIR/historyAndConf | grep TeraSort`
#jobConf=/$TMP_DIR/historyAndConf/`ls /$TMP_DIR/historyAndConf | grep conf`
#echo $crudeHistory
#echo $jobConf

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

echo $0: finished collecting statistics

#ls -lh --full-time $collect > /dev/null # workaround - prevent "tar: file changed as we read it"

#combine all the node's dstat to one file at cluster level
ssh $RES_SERVER cat $collect_dir/\*.dstat.csv \| sort \| $SCRIPTS_DIR/reduce-dstat.awk \> $collect_dir/dstat-$JOB-cluster.csv

echo collecting hadoop master conf dir
echo scp -r $HADOOP_CONF_DIR $RES_SERVER:$collect_dir/$(basename $HADOOP_CONF_DIR) > /dev/null
scp -r $HADOOP_CONF_DIR $RES_SERVER:$collect_dir/$(basename $HADOOP_CONF_DIR) > /dev/null

#if ! tar zcf $collect.tgz $collect 2> /dev/null
#then
#	echo $0: error creating tgz file. Please, Try manually: tar zcf $collect.tgz $collect
#	exit 5
#fi

#echo "$cmd_status is cmd_status"

exit $cmd_status


