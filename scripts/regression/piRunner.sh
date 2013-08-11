#!/bin/bash

prepareTest()
{
	collectionDestDir=$currentLogsDir/$executionFolder
	collectionTempDir=$TMP_DIR/$executionFolder
	mkdir -p $collectionTempDir
	execLogExports=$collectionTempDir/execLogExports.sh
<<CC
	echo "$echoPrefix: cheching pre-requests: bash $SCRIPTS_DIR/preReq.sh -rcph"
	bash $SCRIPTS_DIR/preReq.sh -rcph
	if (($? == $EEC3));then
		echo "
		#!/bin/sh
		export TEST_STATUS=0
		export TEST_ERROR='preReq failed'
		" > $execLogExports
		
		sudo chmod $DIRS_PERMISSIONS $collectionTempDir
		scp -r $collectionTempDir $RES_SERVER:$collectionDestDir/
		continue
	fi
CC
}

currentLogsDir=$1

echoPrefix=`eval $ECHO_PATTERN`
mkdir -p $currentLogsDir
cd $MY_HADOOP_HOME

for sample in `seq 1 $NSAMPLES` ; do
	executionFolder=${TEST_DIR_PREFIX}${PI_DIR_SUFFIX}${SAMPLE_DIR_INFIX}${sample}
	collectionDestDir=$currentLogsDir/$executionFolder
	collectionTempDir=$TMP_DIR/$executionFolder
	mkdir -p $collectionTempDir
	execLogExports=$collectionTempDir/execLogExports.sh
	#prepareTest
	
	echo "$echoPrefix: running pi"
	eval bin/hadoop fs -rmr $PI_HDFS_TEMP_DIR/PiEstimator_TMP*
	export USER_CMD="$CMD_PREFIX $HADOOP_EXAMPLES_JAR_EXP $CMD_PROGRAM $CMD_D_PARAMS $COMPRESSION_D_PARAMETERS $PI_MAPPERS $PI_SAMPLES"
	#export USER_CMD="$CMD_PREFIX $CMD_JAR_EXP $CMD_PROGRAM $CMD_D_PARAMS $PI_MAPPERS $PI_SAMPLES"
	bash $SCRIPTS_DIR/mr-dstatExcel.sh $collectionTempDir $collectionDestDir $executionFolder $execLogExports $PI_JOBS_DIR_NAME
	#*****************#
	source $collectionDestDir/execLogExports.sh
	if [[ -n $SETUP_FAILURE ]];then
		exit $EEC2
	fi
	#*****************#
done
