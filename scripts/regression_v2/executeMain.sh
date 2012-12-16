#!/bin/sh

# Written by Idan Weinstein and Avner BenHanoch
# Date: 2011-04-15
# MODIFIED: 2011-05-25 by idan (added mappers&reduces scale)
# MODIFIED: 2011-07-06 by idan (added params shows , LOG_PREFIX modification)
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

	calculateDataSizeRetVal=$tmp
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

restartingHadoop (){
	echo "$echoPrefix: Restarting Hadoop"
	bash $SCRIPTS_DIR/start_hadoopExcel.sh $@ 
	if (($?==1));then
		echo "$echoPrefix: failed to restart Hadoop" | tee $ERROR_LOG
        exit $EEC1
	fi
}

copyConfFiles() {
	echo "$echoPrefix: Copy conf dir to salves"
	for slave in `cat $1`; do
		scp -r $HADOOP_CONF_DIR/* $slave:$HADOOP_CONF_DIR > /dev/null
	done
}

cd $MY_HADOOP_HOME
export HADOOP_CONF_DIR="$MY_HADOOP_HOME/$HADOOP_CONF_RELATIVE_PATH"
hadoopVersion=`echo $(basename $MY_HADOOP_HOME) | sed s/[.]/_/g`
if [ -z "$hadoopVersion" ];then
	hadoopVersion="unknown-hadoop-version"
fi

echo "$echoPrefix: VERSION:" $hadoopVersion

source $TESTS_PATH/general.sh

if [ -z "$RES_SERVER" ];then
    export RES_SERVER=$DEFAULT_RES_SERVER
fi

totalTests=$TESTS_COUNT
if (($LINE_TO_EXECUTE > -1)) && (($LINE_TO_EXECUTE < $TESTS_COUNT));then
	totalTests=$LINE_TO_EXECUTE
fi

echo "$echoPrefix: prepering directory on the collecting-server ($RES_SERVER) to the logs" 
currentResultsDir=$LOCAL_RESULTS_DIR/${LOGS_DIR_NAME}_${CURRENT_DATE}
sudo ssh $RES_SERVER mkdir -p $currentResultsDir
sudo ssh $RES_SERVER chown -R $USER $currentResultsDir

for line in `seq 1 $totalTests`
do
	# using the correct job file
	dir_name=`ls $TESTS_PATH | grep test${line}`
	testPath=$TESTS_PATH/$dir_name
	source $TESTS_PATH/general.sh
	source $testPath/exports.sh
	echo "source $testPath/exports.sh"
	
	if (( $COMPRESSION==1 )); then
		echo "bash $SCRIPTS_DIR/compressionSet.sh"
		bash $SCRIPTS_DIR/compressionSet.sh
	fi
	
	# start processing test
	echo -e \\n\\n "$echoPrefix: -->>> execution $line. name: $EXEC_NAME" \\n\\n
		
	echo "------------------------------------------"
	echo "********** line is: $line		**********"
	echo "********** DATA_SET= $DATA_SET		**********"
	echo "********** CLUSTER_NODES= $SLAVES_COUNT	**********"
	echo "********** MAX_MAPPERS= $MAX_MAPPERS 	**********"
	echo "********** MAX_REDUCERS= $MAX_REDUCERS 	**********"
	echo "********** NSAMPLES= $NSAMPLES 		**********"
	echo "********** TERAVALIDATE = $TERAVALIDATE 	**********"			
	echo "------------------------------------------"
	echo ""
				
	if (($RESTART_HADOOP==1))
	then
		if (($UNSPREAD_CONF_FLAG == 0));then
			cp $testPath/*.xml ${HADOOP_CONF_DIR}/
			cp $testPath/masters ${HADOOP_CONF_DIR}/
			cp $testPath/slaves ${HADOOP_CONF_DIR}/
		fi
		
		host=`head -1 $HADOOP_CONF_DIR/slaves`
		host_tail=`[[  $host =~ "-" ]] && echo $host | sed 's/.*-//' || echo lan`
		for host in `cat $HADOOP_CONF_DIR/slaves`; do
				if [ $host_tail !=  `[[  $host =~ "-" ]] && echo $host | sed 's/.*-//' || echo lan` ];then
					echo "$echoPrefix: slave\'s hostnames are not matching for the same network interface: `cat $HADOOP_CONF_DIR/slaves`" | tee $ERROR_LOG
					exit $EEC1
				fi
		done

		if [ $host_tail == "lan" ];then
			echo "$echoPrefix: slave\'s hostname are not tailed with network interface identifier (hostname-ib , hostname-1g or hostname-ib) hadoop traffic will use LAN interface" | tee $ERROR_LOG
			exit $EEC1
		fi

		if (($UNSPREAD_CONF_FLAG == 0));then
			copyConfFiles $HADOOP_CONF_DIR/slaves
		fi
		echo "$echoPrefix: Setting slave.host.name to slaves and master"
		bash ${SCRIPTS_DIR}/set_hadoop_slave_property.sh --hadoop-conf-dir=${HADOOP_CONF_DIR} --host-suffix=${INTERFACE_ENDING}
		bin/slaves.sh ${SCRIPTS_DIR}/set_hadoop_slave_property.sh --hadoop-conf-dir=${HADOOP_CONF_DIR} --host-suffix=${INTERFACE_ENDING}

		if (($FIRST_STARTUP == 1));then
			restartParam=" -restart"
		else
			restartParam=""
		fi
		restartingHadoop $RESTART_HADOOP_MAX_ATTEMPTS $restartParam	
	fi
	
	export LOG_PREFIX=${hadoopVersion}.${line}.${host_tail}.shuffC${SHUFFLE_PROVIDER}.shuffP${SHUFFLE_CONSUMER}.${clusterNodes}n.${DISKS}d.${$}pid
	
	echo "$echoPrefix: #slaves=$clusterNodes"
	echo "$echoPrefix: #spindles=$DISKS"
	echo "$echoPrefix: LOG_PREFIX=$LOG_PREFIX"
	
	case $PROGRAM in
		"terasort"	) 
			# forcreating Teragen-jobs in the size of the ram, in order to flush it
			calculateDataSize $RAM_SIZE
			export TOTAL_DATA_SET=$calculateDataSizeRetVal
			echo "$echoPrefix: new data-set is: $DATA_SET"
			currentExecDir=$currentResultsDir/$TERASORT_JOBS_DIR_NAME/${EXEC_DIR_PREFIX}${line}-${EXEC_NAME}
			echo "echoPrefix: running Terasort"
			bash ${SCRIPTS_DIR}/terasortRunner.sh $currentExecDir
		;;
		"TestDFSIO"	) 
			currentExecDir=$currentResultsDir/$TEST_DFSIO_JOBS_DIR_NAME/${EXEC_DIR_PREFIX}${line}-${EXEC_NAME}
			echo "echoPrefix: running TestDFSIO"
			bash ${SCRIPTS_DIR}/testDFSIORunner.sh $currentExecDir
		;;	
		"pi"		) 
			currentExecDir=$currentResultsDir/$PI_JOBS_DIR_NAME/${EXEC_DIR_PREFIX}${line}-${EXEC_NAME}
			echo "echoPrefix: running TestDFSIO"
			bash ${SCRIPTS_DIR}/piRunner.sh $currentExecDir
		;;	
		*			) 
			echo "$echoPrefix: unknown program was selected ($PROGRAM)" | tee $ERROR_LOG
			exit $EEC1
		;;	
	esac
	
	testLogExports=$currentExecDir/testLogExports.sh
	cat $testPath/exports.sh > $testLogExports
	echo "
		export tslDATA_SET='$TOTAL_DATA_SET'
		export tslSAMPLES='$NSAMPLES'
	" >> $testLogExports
	
	echo -e \\n\\n\\n\\n\\n
	echo "$echoPrefix: finished line #$line"
	echo -e \\n\\n\\n\\n\\n
	
	if (($TEST_RUN_FLAG == 1));then
		echo "$echoPrefix: test-run mode - breaking after one test"
		break
	fi
done

echo "$echoPrefix: stopping all hadoop processes"
bin/stop-all.sh

echo "
	#!/bin/sh
	export HADOOP_VERSION='$hadoopVersion'
	export CURRENT_LOCAL_RESULTS_DIR='$currentResultsDir'
	export TERASORT_LOGS_RELATIVE_DIR='$TERASORT_JOBS_DIR_NAME'
	export TEST_DFSIO_LOGS_RELATIVE_DIR='$TEST_DFSIO_JOBS_DIR_NAME'
	export PI_LOGS_RELATIVE_DIR='$PI_JOBS_DIR_NAME'
	export RES_SERVER=$RES_SERVER
	export COMPRESSION='$COMPRESSION'
" > $TMP_DIR/executeExports.sh
