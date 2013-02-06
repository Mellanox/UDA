#!/bin/bash


currentLogsDir=$1

echoPrefix=`eval $ECHO_PATTERN`
mkdir -p $currentLogsDir
cd $MY_HADOOP_HOME

for sample in `seq 1 $NSAMPLES` ; do
	echo "$echoPrefix: running pi"
	executionFolder=${TEST_DIR_PREFIX}${PI_DIR_POSTFIX}${SAMPLE_DIR_INFIX}${sample}
	collectionTempDir=$TMP_DIR/$executionFolder
	collectionDestDir=$currentLogsDir/$executionFolder
	mkdir -p $collectionTempDir
	execLogExports=$collectionTempDir/execLogExports.sh
	eval bin/hadoop fs -rmr $PI_HDFS_TEMP_DIR/PiEstimator_TMP*
	export USER_CMD="$CMD_PREFIX $CMD_JAR $CMD_PROGRAM $CMD_D_PARAMS $PI_MAPPERS $PI_SAMPLES"
	bash $SCRIPTS_DIR/mr-dstatExcel.sh $collectionTempDir $collectionDestDir $executionFolder $execLogExports $PI_JOBS_DIR_NAME
done