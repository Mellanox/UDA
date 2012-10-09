#!/bin/bash

echoPrefix=$(basename $0)
recentNfsResultsDir=$NFS_RESULTS_DIR/recentLogs
echo $recentNfsResultsDir
rm -rf $recentNfsResultsDir
echo $recentNfsResultsDir
mkdir $recentNfsResultsDir
#CURRENT_NFS_RESULTS_DIR
cp -rf $CURRENT_NFS_RESULTS_DIR $recentNfsResultsDir

errorLog=$CURRENT_NFS_RESULTS_DIR/`basename $ERROR_LOG`
if ! cat $errorLog | grep -c "";then
	rm -f $errorLog
fi

# zipping the results
cd $CURRENT_NFS_RESULTS_DIR/..
#gzip -rf $CURRENT_NFS_RESULTS_DIR
if ! tar zcf $CURRENT_NFS_RESULTS_DIR.tgz $CURRENT_NFS_RESULTS_DIR 2> /dev/null
then
	echo "$echoPrefix: error creating tgz file. Please, Try manually: tar zcf $CURRENT_NFS_RESULTS_DIR.tgz $CURRENT_NFS_RESULTS_DIR" | tee $ERROR_LOG
	exit 1
fi
#rm -rf $CURRENT_NFS_RESULTS_DIR

#failFlag=0

#echo "$echoPrefix: deleting HDFS"
#$MY_HADOOP_HOME/bin/hadoop -rmr / &

#echo "$echoPrefix: deleting all temp directories"
#$MY_HADOOP_HOME/bin/slaves.sh rm -rf $TMP_DIR/\* &

#for job in `jobs -p`
#do
#    wait $job | let "failFlag+=1"
#done

#if (( $failFlag == 0 ));then
#	echo "$echoPrefix: deletion succeeded"
#else
#	echo "$echoPrefix: deletion  failed"
#fi