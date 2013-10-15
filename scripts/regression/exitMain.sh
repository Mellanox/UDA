#!/bin/bash

echoPrefix=`eval $ECHO_PATTERN`
recentNfsResultsDir=$RECENT_JOB_DIR
sudo mkdir $recentNfsResultsDir
#sudo chgrp -R $GROUP_NAME $recentNfsResultsDir
#sudo chgrp -R $GROUP_NAME $CURRENT_NFS_RESULTS_DIR

#cp -rf $CURRENT_NFS_RESULTS_DIR/* $recentNfsResultsDir TODO: uncomment it

errorLog=$CURRENT_NFS_RESULTS_DIR/$ERROR_LOG_FILE_NAME
if ! cat $errorLog | grep -c "";then
	rm -f $errorLog
fi

#if [[ -n $RESTART_CLUSTER_CONF_FLAG ]];then
#	sudo pdsh -w $RELEVANT_SLAVES_BY_COMMAS "bash $EXIT_SCRIPTS_SLAVES | tee $STATUS_DIR/exitScriptValidation.txt"
#fi

# zipping the results
if (($ZIP_FLAG==1));then
	cd `dirname $CURRENT_NFS_RESULTS_DIR`
	jobName=`basename $CURRENT_NFS_RESULTS_DIR`
	#gzip -rf $CURRENT_NFS_RESULTS_DIR
	echo "$echoPrefix: Current dir is"
	pwd
	echo "$echoPrefix: Performing tar zcf $jobName.tgz $jobName"
	tar zcf $jobName.tgz $jobName 2> $DEV_NULL_PATH
	if [[ "$?" != "0" ]];
	then
		echo "$echoPrefix: error creating tgz file. Please, Try manually: tar zcf $CURRENT_NFS_RESULTS_DIR.tgz $CURRENT_NFS_RESULTS_DIR" | tee $ERROR_LOG
		exit 1
	fi
	echo "$echoPrefix: `basename $CURRENT_NFS_RESULTS_DIR` had compressed successfully"
	echo "$echoPrefix: deleting the directory $CURRENT_NFS_RESULTS_DIR"
	rm -rf $CURRENT_NFS_RESULTS_DIR/
fi

for machine in $ALL_MACHINES_BY_SPACES;do
	bash $SCRIPTS_DIR/functionsLib.sh "set_hostnames" "$machine" "$machine" 
done

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
