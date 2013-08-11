#!/bin/bash

echoPrefix=$(basename $0)

reportSubject=$REPORT_SUBJECT
if (($TEST_RUN_FLAG == 1));then
	currentNfsResultsDir=$NFS_RESULTS_DIR/testRun_$CURRENT_DATE
else
	currentNfsResultsDir=$NFS_RESULTS_DIR/smoke_$CURRENT_DATE
fi

if ! mkdir $currentNfsResultsDir;then
	echo "$echoPrefix: failling to create $currentNfsResultsDir" | tee $ERROR_LOG
	exit $EEC1
fi

	# copying the logs dirs
echo "$echoPrefix: the NFS collect dir is $CURRENT_NFS_RESULTS_DIR"
echo "$echoPrefix: collecting logs"
cp -r $CURRENT_LOCAL_RESULTS_DIR $currentNfsResultsDir > /dev/null
cp -r $ERROR_LOG $currentNfsResultsDir > /dev/null
#cp -rf $recentNfsResultsDir $CURRENT_NFS_RESULTS_DIR
	# copying the tests dirs
echo "$echoPrefix: collecting test-files"
cp -r $TESTS_PATH $currentNfsResultsDir > /dev/null
	# copying the csv configuration file
echo "$echoPrefix: collecting csv-configuration-file"
cp $CSV_FILE $currentNfsResultsDir > /dev/null

chmod -R 775 $currentNfsResultsDir

currentLogsDir=`ls $currentNfsResultsDir | grep logs`
currentLogsDir=`basename $CURRENT_LOCAL_RESULTS_DIR`

echo "
	#!/bin/sh
	export CURRENT_NFS_RESULTS_DIR='$currentNfsResultsDir'
	export STATISTICS_INPUT_DIR='$currentNfsResultsDir/$currentLogsDir' # the same as CURRENT_NFS_RESULTS_LOGS_DIR
" > $TMP_DIR/collectExports.sh
