#!/bin/sh

# Written by Idan Weinstein and Avner BenHanoch
# Date: 2011-04-15
# MODIFIED: 2011-05-25 by idan (added mappers&reduces scale)
# MODIFIED: 2011-07-06 by idan (added params shows , logPrefix modification)
# MODIFIED: 2011-07-20 by idan (added #nodes scale & retry mechanism)
# MODIFIED: 2012-08-09 br oriz - changed to support command-line executions
#	    MODIFICATIONS:
#	 1) the script have now two part - input & parsing part and execution part.
#	    the two parts can run individually or one ater the other (see options)
#	 2) the hadoop isn't get restarted after every execution - only when crutial
#	    parameters changed. in a case of execution failures- the hadoop is restarted
#	    only after more then one failure (instead of one)
#	 3) the slaves and masters files are distributed to the masters nodes,
#	    instead of marking an existed files (like in "mark_slaves.sh")
#	 4) the interface input manage moved to the parsing script ("parseTest.awk")
#	 5) if the parsing script found errors, it will warn and won't execute th jobs
#	    NOTES:
#	 1) the script don't support execution with differant slaves count in the same
#	    CSV-file - it couse problems with restarting the hadoop

executionsMaxAttempts=5
restartHadoopMaxAttemps=5
teragenCounter=0
echoPrefix=$(basename $0)

calculateDataSize (){
	sum=0
	tmp=0
	ramsize=$1
	
	if (( ${DATA_SET} <= ${ramsize} ))
			then
			tmp="${DATA_SET} " # dont earse this space!!
			sum=$ramsize
			while (($sum>0))
			do
					tmp="${tmp}${DATA_SET} "
					sum=$((${sum}-${DATA_SET}))
			done

	fi

	export DATA_SET=$tmp
}
	
errorHandler (){
	# there is a scenario that error occured but the return value will be 0 - 
	# when start_hadoopExcel.sh or mkteragenExcel.sh prints their usage-print,
	# (which it a unsuccessfull scenario for this script's purposes).
	# in such case this script won't recognized the problem
    if (($1==1));then
		echo "$echoPrefix: $2" | tee $ERROR_LOG
        exit $EEC1
	fi
}

teragenning (){
	echo "$echoPrefix: Teragenning"
	bash $SCRIPTS_DIR/mkteragenExcel.sh
    errorHandler $? "Teragen Failed"
	teragenCounter=$((teragenCounter+1))
}

restartingHadoop (){
	echo "$echoPrefix: Restarting Hadoop"
	bash $SCRIPTS_DIR/start_hadoopExcel.sh $@ 
	errorHandler $? "failed to restart Hadoop"
	return $?
}

copyConfFiles() {
	echo "$echoPrefix: Copy conf dir to salves"
	for slave in `cat $1`; do
		scp -r $HADOOP_CONF_DIR/* $slave:$HADOOP_CONF_DIR > /dev/null
	done
}

cd $MY_HADOOP_HOME

for line in `seq 1 $TOTAL_TESTS` ; do
	# using the correct job file
	dir_name=`ls $TESTS_PATH | grep $line`
	testPath=${TESTS_PATH}/${dir_name}
	source $testPath/exports.sh
	execDir=$CURRENT_LOCAL_RESULTS_DIR/exec${line}-${EXEC_NAME}
	mkdir -p $execDir
	
	# start processing test
	echo -e \\n\\n "$echoPrefix: -->>> execution $line. name: $EXEC_NAME" \\n\\n
	
	clusterNodes=$SLAVES_COUNT
	mappers=$MAX_MAPPERS
	reducers=$MAX_REDUCERS
	
	echo "------------------------------------------"
	echo "********** line is: $line		**********"
	echo "********** DATA_SET= $DATA_SET		**********"
	echo "********** CLUSTER_NODES= $clusterNodes	**********"
	echo "********** MAX_MAPPERS= $mappers 	**********"
	echo "********** MAX_REDUCERS= $reducers 	**********"
	echo "********** NSAMPLES= $NSAMPLES 		**********"
	echo "********** TERAVALIDATE = $TERAVALIDATE 	**********"			
	echo "------------------------------------------"
	echo ""

	# for creating Teragen-jobs in the size of the ram, in order to flush it
	calculateDataSize $RAM_SIZE
	echo "$echoPrefix: new data-set is: $DATA_SET"

	logPrefix=${HADOOP_VERSION}.${line}.${host_tail}.shuffC${SHUFFLE_PROVIDER}.shuffP${SHUFFLE_CONSUMER}.${clusterNodes}n.${DISKS}d.${$}pid
	
	echo "$echoPrefix: #slaves=$clusterNodes"
	echo "$echoPrefix: #spindles=$DISKS"
	echo "$echoPrefix: logPrefix=$logPrefix"

	teragenExist=`hadoop fs -ls $TERAGEN_DIR | grep -c teradata`

	if (($TERAGEN == 1)) || ((! $TERAGEN && ! $teragenExist))
	then # if there is no teragen data or we need to generate a new one
		currentTeragen=""
		if (($teragenExist != 0));then
			currentTeragen=$HDFS_PREFIX/teragen/$CURRENT_DATE
		else
			teragenPathEnding=`basename $TERAGEN_DIR`
			if [[ $teragenPathEnding != "teragen" ]];then
				currentTeragen=$TERAGEN_DIR
			else
				currentTeragen=$TERAGEN_DIR/$CURRENT_DATE
			fi
		fi
		export CURRENT_TERAGEN=$currentTeragen
		teragenning
	else
		export CURRENT_TERAGEN=$TERAGEN_DIR
	fi
	
	export CURRENT_TERASORT=$TERASORT_DIR/$CURRENT_DATE
	export CURRENT_TERAVAL=$TERAVAL_DIR/$CURRENT_DATE
	
	for sample in `seq 1 $NSAMPLES`
	do				
	# delete this dummy
		#DATA_SET="16"
		ds_n=0
		
		dataSet=$DATA_SET

		for ds in $dataSet
		do
			attempt=0
			code=0
			attemptCode=1
			ds_n=$((ds_n+1));

			while (($attemptCode!=0)) && (($attempt<$executionsMaxAttempts))
			do
				#echo "$echoPrefix: Cleaning /terasort/output HDFS library"
				#echo "$echoPrefix: hadoop fs -rmr /terasort/output"
				#hadoop fs -rmr /terasort/output
				#sleep 10

				#totalReducers=$(($clusterNodes * $reducers))
				#if [[ $DATA_SET_TYPE == "node" ]];then
				#		totalDataSet=$(($ds * $clusterNodes))
				#else
				#		totalDataSet=$ds
				#fi			

				totalDataSet=$ds

				echo "$echoPrefix: Running test on cluster of $clusterNodes slaves with $mappers mappers, $reducers reducers per TT and total of $totalReducers reducers"
				# flushing the cache and cleaning log files						
				#echo "$echoPrefix: Cleaning buffer caches" 
				#sudo bin/slaves.sh $SCRIPTS_DIR/cache_flush.sh
				#TODO: above will only flash OS cache; still need to flash disk cache
				#sleep 3

				#echo "$echoPrefix: Cleaning logs directories (history&userlogs)"
				#rm -rf $MY_HADOOP_HOME/logs/userlogs/*
				#rm -rf $MY_HADOOP_HOME/logs/history/*
				#bin/slaves.sh rm -rf $MY_HADOOP_HOME/logs/userlogs/*
				#bin/slaves.sh rm -rf $MY_HADOOP_HOME/logs/history/*

				# this is the command to run:
				export INPUTDIR="$CURRENT_TERAGEN/teradata${totalDataSet}G.${ds_n}"
				export OUTPUTDIR="$CURRENT_TERASORT/${totalDataSet}G.${ds_n}.${attempt}att"
				export USER_CMD="${CMD} $INPUTDIR $OUTPUTDIR"
				echo "$echoPrefix: the command is: $USER_CMD"

				echo "$echoPrefix: job=${logPrefix}.N${ds}G.N${mappers}m.N${reducers}r.T${totalDataSet}G.T${totalReducers}r.log.${sample}"
				job=${logPrefix}.N${ds}G.${ds_n}.N${mappers}m.N${reducers}r.T${totalDataSet}G.T${totalReducers}r.log.${sample}

				# executing the job and making staticsics
				
				echo "$echoPrefix: calling mr-dstat for $USER_CMD attempt $attempt"

				#collectDir=$execDir/sample-${sample}
				#executionFolder=${job}_attempt${attempt}
				#mkdir $TMP_DIR/$executionFolder
				#execLogExports=$TMP_DIR/$executionFolder/execLogExports.sh
				
				executionFolder=${job}_attempt${attempt}
				collectionTempDir=$TMP_DIR/$executionFolder
				collectionDestDir=$execDir/sample-${sample}/$executionFolder
				mkdir -p $collectionTempDir
				execLogExports=$collectionTempDir/execLogExports.sh
				echo "	
					#!/bin/sh
					export exlTERAGEN_COUNTER='$teragenCounter'	
				" >> $execLogExports
				#bash $SCRIPTS_DIR/mr-dstatExcel.sh $collectDir $executionFolder $execLogExports
				bash $SCRIPTS_DIR/mr-dstatExcel.sh $collectionTempDir $collectionDestDir $executionFolder $execLogExports
				attemptCode=$?

				if (($attemptCode != 0));then
					echo "$echoPrefix: attempt code: $attemptCode"
					echo "$echoPrefix: FAILED ${job}_attempt${attempt}"
				fi
				
				attempt=$((attempt+1))			
			done # while ((attemptCode!=0)) && ((attempt<executionsMaxAttempts))
		
			if (($attemptCode == 0));then
				echo "$echoPrefix: ${job}_attempt${attempt} SUCCESS"
			fi
			
			if (($TEST_RUN_FLAG == 1));then
				break
			fi
		done # ds
		if (($TEST_RUN_FLAG == 1));then
			break
		fi
	done # sample

	testLogExports=$execDir/testLogExports.sh
			
	cat $testPath/exports.sh > $testLogExports
	echo "
		export tslDATA_SET='$totalDataSet'
		export tslSAMPLES='$NSAMPLES'
	" >> $testLogExports
	
	echo -e \\n\\n\\n\\n\\n\\n\\n\\n
	echo "$echoPrefix: finished line #$line"
	echo -e \\n\\n\\n\\n\\n\\n\\n\\n
	
	if (($TEST_RUN_FLAG == 1));then
		break
	fi
done # line

#echo "$echoPrefix: stopping all hadoop processes"
#bin/stop-all.sh

echo "
#!/bin/sh
" > $TMP_DIR/executeExports.sh

