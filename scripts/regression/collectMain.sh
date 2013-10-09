#!/bin/bash

attemptCommand()
{
	local cmd=$1
	bash $SCRIPTS_DIR/functionsLib.sh "execute_command" 10 60 "$cmd"
	if (($? != 0)); then
		echo "$echoPrefix: Failed to execute $cmd after 5 retries" | tee $ERROR_LOG
		exit $EEC1
	fi
}

#if [[ -n $A_M ]];then
#	echo $CEC
#fi
echoPrefix=`eval $ECHO_PATTERN`
#reportSubject=$REPORT_SUBJECT
recentNfsResultsDir=$NFS_RESULTS_DIR/$RECENT_JOB_DIR_NAME
sudo rm -rf $recentNfsResultsDir

if (($TEST_RUN_FLAG == 1));then
	dirType=$TEST_RUN_DIR_PREFIX
else
	dirType=${DAILY_REGRESSION_PREFIX}$SMOKE_RUN_DIR_PREFIX
fi
currentNfsTotalResultsDir=$NFS_RESULTS_DIR/${dirType}_$CURRENT_DATE
currentNfsEnvResultsDir=$currentNfsTotalResultsDir/$ENV_FIXED_NAME

attemptCommand "mkdir -p $currentNfsEnvResultsDir"

echo "$echoPrefix: the NFS collect dir is $currentNfsEnvResultsDir"

	# copying the logs dirs
echo "$echoPrefix: collecting logs"
logsDestDir=$currentNfsEnvResultsDir/$LOGS_DIR_NAME
attemptCommand "mkdir -p $logsDestDir"
attemptCommand "scp -r $RES_SERVER:$CURRENT_LOCAL_RESULTS_DIR/* $logsDestDir > $DEV_NULL_PATH"
	# copying the tests dirs
echo "$echoPrefix: collecting test-files"
confsDestDir=$currentNfsEnvResultsDir/$TESTS_CONF_DIR_NAME
attemptCommand "mkdir $confsDestDir"
attemptCommand "cp -r $TESTS_CONF_DIR/* $confsDestDir > $DEV_NULL_PATH"
	# copying the csv configuration file
echo "$echoPrefix: collecting csv-configuration-file"
attemptCommand "cp $TEST_CONF_FILE $currentNfsEnvResultsDir > $DEV_NULL_PATH"
	# copying the coverity files
#echo "$echoPrefix: collecting code coverage files"

if (($CODE_COVE_FLAG == 1)); then
	for machine in $MASTER $SLAVES_BY_SPACES;do
		#echo "ssh $machine scp $COVFILE $RES_SERVER:/tmp/${machine}_coverage.cov"
		newCovfileName=${ENV_FIXED_NAME}_${machine}${CODE_COVERAGE_FILE_SUFFIX}
		sudo chown -R $USER $CODE_COVERAGE_FINAL_DIR
		sudo scp $machine:$CODE_COVERAGE_FILE $CODE_COVERAGE_FINAL_DIR/$newCovfileName
	done
fi 

errorExist=`grep -c "" $ERROR_LOG`
if (($errorExist != 0));then
	echo "$echoPrefix: collecting the errors-log"
	cp -r $ERROR_LOG $currentNfsEnvResultsDir > $DEV_NULL_PATH
fi

chmod -R $DIRS_PERMISSIONS $currentNfsEnvResultsDir
#$CURRENT_NFS_RESULTS_DIR/$LOGS_DIR_NAME
echo "
	#!/bin/sh
	export CURRENT_NFS_RESULTS_DIR='$currentNfsTotalResultsDir'
	export CURRENT_NFS_ENV_RESULTS_DIR='$currentNfsEnvResultsDir'
	export REPORT_INPUT_DIR='$logsDestDir'
	export COVERAGE_DEST_DIR='$CODE_COVERAGE_FINAL_DIR'
	export RECENT_JOB_DIR='$recentNfsResultsDir'
#export A_M='DELETE_ME'
" > $SOURCES_DIR/collectExports.sh
