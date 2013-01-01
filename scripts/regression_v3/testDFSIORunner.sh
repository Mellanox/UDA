#!/bin/bash

teragenning (){
	nmaps=$((SLAVES_COUNT*MAX_MAPPERS))
	size=$((RAM_SIZE*SLAVES_COUNT*TERAGEN_GIGA_MULTIPLIER))
	cmd="bin/hadoop jar $HADOOP_EXAMPLES_JAR teragen -Dmapred.map.tasks=${nmaps} ${size}"
	
	echo "$echoPrefix: teragenning"
	bash $SCRIPTS_DIR/generateData.sh "$cmd" $DATA_FOR_RAM_FLUSHING_DIR "rmr" "clear"
	if (($?==1));then
		echo "$echoPrefix: teragen failed" | tee $ERROR_LOG
        exit $EEC1
	fi
}

DFSIOclear(){
	echo "$echoPrefix: TestDFSIO clear"
	eval "$CMD_PREFIX $CMD_JAR $CMD_PROGRAM -clear"
}

DFSIOwrite(){
	echo "$echoPrefix: TestDFSIO write"
	executionFolder=${TEST_DIR_PREFIX}${sample}${TEST_DFSIO_WRITE_DIR_POSTFIX}
	collectionTempDir=$TMP_DIR/$executionFolder
	collectionDestDir=$currentLogsDir/$executionFolder
	mkdir -p $collectionTempDir
	execLogExports=$collectionTempDir/execLogExports.sh
	export USER_CMD="$CMD_PREFIX $CMD_JAR $CMD_PROGRAM $CMD_D_PARAMS $CMD_TEST_DFSIO_PARAMS -write"
	bash $SCRIPTS_DIR/mr-dstatExcel.sh $collectionTempDir $collectionDestDir $executionFolder $execLogExports $TEST_DFSIO_WRITE_DIR
}

DFSIOread(){
	echo "$echoPrefix: TestDFSIO read"
	executionFolder=${TEST_DIR_PREFIX}${sample}${TEST_DFSIO_READ_DIR_POSTFIX}
	collectionTempDir=$TMP_DIR/$executionFolder
	collectionDestDir=$currentLogsDir/$executionFolder
	mkdir -p $collectionTempDir
	execLogExports=$collectionTempDir/execLogExports.sh
	export USER_CMD="$CMD_PREFIX $CMD_JAR $CMD_PROGRAM $CMD_D_PARAMS $CMD_TEST_DFSIO_PARAMS -read"
	bash $SCRIPTS_DIR/mr-dstatExcel.sh $collectionTempDir $collectionDestDir $executionFolder $execLogExports $TEST_DFSIO_READ_DIR
}

currentLogsDir=$1

echoPrefix=$(basename $0)
mkdir -p $currentLogsDir
cd $MY_HADOOP_HOME

for sample in `seq 1 $NSAMPLES` ; do
	if ((`bin/hadoop fs -ls / | grep -c $TEST_DFSIO_DIR` == 1));then
		DFSIOclear
	fi
	DFSIOwrite
	sudo bin/slaves.sh $SCRIPTS_DIR/cache_flush.sh
	teragenning
	sudo bin/slaves.sh $SCRIPTS_DIR/cache_flush.sh
	DFSIOread
	DFSIOclear
done
