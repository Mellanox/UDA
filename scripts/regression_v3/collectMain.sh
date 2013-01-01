#!/bin/bash

echoPrefix=$(basename $0)

reportSubject=$REPORT_SUBJECT
if (($TEST_RUN_FLAG == 1));then
	currentNfsResultsDir=$NFS_RESULTS_DIR/${TEST_RUN_DIR_PREFIX}$CURRENT_DATE
else
	currentNfsResultsDir=$NFS_RESULTS_DIR/${DAILY_REGRESSION_PREFIX}${SMOKE_RUN_DIR_PREFIX}$CURRENT_DATE
fi

if ! mkdir $currentNfsResultsDir;then
	echo "$echoPrefix: failling to create $currentNfsResultsDir" | tee $ERROR_LOG
	exit $EEC1
fi
echo "$echoPrefix: the NFS collect dir is $currentNfsResultsDir"

	# copying the logs dirs
echo "$echoPrefix: collecting logs"
logsDestDir=$currentNfsResultsDir/$LOGS_DIR_NAME
mkdir -p $logsDestDir
scp -r $RES_SERVER:$CURRENT_LOCAL_RESULTS_DIR/* $logsDestDir > /dev/null
	# copying the tests dirs
echo "$echoPrefix: collecting test-files"
confsDestDir=$currentNfsResultsDir/$CONFS_DIR_NAME
mkdir $confsDestDir
cp -r $TESTS_PATH/* $confsDestDir > /dev/null
	# copying the csv configuration file
echo "$echoPrefix: collecting csv-configuration-file"
cp $CSV_FILE $currentNfsResultsDir > /dev/null
	# copying the coverity files
echo "$echoPrefix: collecting code coverage files"

mergeCommand=""
if (( $CODE_COVE_FLAG )); then
#for slave in `cat $confDir/slaves`
	for slave in `cat $MY_HADOOP_HOME/conf/slaves`
	do
		#echo "ssh $slave scp $COVFILE $RES_SERVER:/tmp/${slave}_coverage.cov"
		ssh $slave scp $COVFILE $RES_SERVER:/tmp/${slave}_coverage.cov
		mergeCommand="/tmp/${slave}_coverage.cov ${mergeCommand}"
		echo "$(basename $0) mergeCommand: $mergeCommand"
	done 
	
echo "mergeCommand :$mergeCommand"
echo "merging cov files:" 
covmerge -c -f /tmp/total_cov.cov ${mergeCommand}

coverageDestDir=$currentNfsResultsDir/$COVERAGE_DIR_NAME
mkdir -p $coverageDestDir

echo "scp /tmp/total_cov.cov $coverageDestDir"
scp /tmp/total_cov.cov $coverageDestDir
scp -r $RES_SERVER:$CODE_COVERAGE_DIR/* $coverageDestDir > /dev/null

covdir -f /tmp/total_cov.cov > $coverageDestDir/cov_report.txt

fi 

errorExist=`grep -c "" $ERROR_LOG`
if (($errorExist != 0));then
	echo "$echoPrefix: collecting the errors-log"
	cp -r $ERROR_LOG $currentNfsResultsDir > /dev/null
fi



chmod -R 775 $currentNfsResultsDir
#$CURRENT_NFS_RESULTS_DIR/$LOGS_DIR_NAME
echo "
	#!/bin/sh
	export CURRENT_NFS_RESULTS_DIR='$currentNfsResultsDir'
	export REPORT_INPUT_DIR='$currentNfsResultsDir/$LOGS_DIR_NAME'
	export COVERAGE_DEST_DIR='$coverageDestDir'
" > $TMP_DIR/collectExports.sh
