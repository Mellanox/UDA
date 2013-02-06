#!/bin/bash

echoPrefix=`eval $ECHO_PATTERN`
recentNfsResultsDir=$NFS_RESULTS_DIR/$RECENT_JOB_DIR_NAME
echo $recentNfsResultsDir
sudo rm -rf $recentNfsResultsDir
echo $recentNfsResultsDir
mkdir $recentNfsResultsDir
chgrp -R $GROUP_NAME $recentNfsResultsDir
chgrp -R $GROUP_NAME $CURRENT_NFS_RESULTS_DIR

cp -rf $CURRENT_NFS_RESULTS_DIR/* $recentNfsResultsDir

errorLog=$CURRENT_NFS_RESULTS_DIR/`basename $ERROR_LOG`
if ! cat $errorLog | grep -c "";then
	rm -f $errorLog
fi

if [[ -n $RESTART_CLUSTER_CONF_FLAG ]];then
	sudo pdsh -w $RELEVANT_SLAVES_BY_COMMAS "bash $EXIT_SCRIPTS_SLAVES | tee $STATUS_DIR/hugepageValidation.txt"
fi

# zipping the results
if (($ZIP_FLAG==1));then
	cd $CURRENT_NFS_RESULTS_DIR/..
	#gzip -rf $CURRENT_NFS_RESULTS_DIR
	if ! tar zcf $CURRENT_NFS_RESULTS_DIR.tgz $CURRENT_NFS_RESULTS_DIR 2> /dev/null
	then
		echo "$echoPrefix: error creating tgz file. Please, Try manually: tar zcf $CURRENT_NFS_RESULTS_DIR.tgz $CURRENT_NFS_RESULTS_DIR" | tee $ERROR_LOG
		exit 1
	fi
	echo "$echoPrefix: `basename $CURRENT_NFS_RESULTS_DIR` had compressed successfully"
	echo "$echoPrefix: deleting the directory $CURRENT_NFS_RESULTS_DIR"
	rm -rf $CURRENT_NFS_RESULTS_DIR/
fi


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