#!/bin/bash

teragenning (){
	echo "$echoPrefix: Teragenning"
	tmpTeragenDir="/TestDFSIOteragen"
	teragenSize=$((RAM_SIZE*10000000*SLAVES_COUNT))
	mapTasks=$((SLAVES_COUNT*MAX_MAPPERS))
	eval bin/hadoop jar hadoop*examples*.jar teragen -Dmapred.map.tasks=$mapTasks $teragenSize $tmpTeragenDir
	bin/hadoop fs -rmr $tmpTeragenDir
}

DFSIOclear(){
	echo "$echoPrefix: TestDFSIO clear"
	eval "$CMD_PREFIX $CMD_JAR $CMD_PROGRAM -clear"
}

DFSIOwrite(){
	echo "$echoPrefix: TestDFSIO write"
	executionFolder=${TEST_DIR_PREFIX}${WRITE_DIR_POSTFIX}
	collectionTempDir=$TMP_DIR/$executionFolder
	collectionDestDir=$currentLogsDir/$executionFolder
	mkdir -p $collectionTempDir
	execLogExports=$collectionTempDir/execLogExports.sh
	export USER_CMD="$CMD_PREFIX $CMD_JAR $CMD_PROGRAM $CMD_D_PARAMS $CMD_END_PARAMS -write"
	bash $SCRIPTS_DIR/mr-dstatExcel.sh $collectionTempDir $collectionDestDir $executionFolder $execLogExports $TEST_DFSIO_WRITE_DIR
}

DFSIOread(){
	echo "$echoPrefix: TestDFSIO read"
	executionFolder=${TEST_DIR_PREFIX}${READ_DIR_POSTFIX}
	collectionTempDir=$TMP_DIR/$executionFolder
	collectionDestDir=$currentLogsDir/$executionFolder
	mkdir -p $collectionTempDir
	execLogExports=$collectionTempDir/execLogExports.sh
	export USER_CMD="$CMD_PREFIX $CMD_JAR $CMD_PROGRAM $CMD_D_PARAMS $CMD_END_PARAMS -read"
	bash $SCRIPTS_DIR/mr-dstatExcel.sh $collectionTempDir $collectionDestDir $executionFolder $execLogExports $TEST_DFSIO_READ_DIR
}

currentLogsDir=$1

echoPrefix=$(basename $0)
mkdir -p $currentLogsDir
cd $MY_HADOOP_HOME
#/benchmarks/TestDFSIO/io_data
if ((`bin/hadoop fs -ls / | grep -c $TEST_DFSIO_DIR` == 1));then
	DFSIOclear
fi
DFSIOwrite
sudo bin/slaves.sh $SCRIPTS_DIR/cache_flush.sh
teragenning
sudo bin/slaves.sh $SCRIPTS_DIR/cache_flush.sh
DFSIOread
DFSIOclear
