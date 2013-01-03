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

echoPrefix=`eval $ECHO_PATTERN`

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
		scp -r $HADOOP_CONFIGURATION_DIR/* $slave:$HADOOP_CONFIGURATION_DIR > /dev/null
	done
}

ceilingDivide() 
{
	# Normal integer divide.
	#ceilingResult=$(($1/$2))
	ceilingResult=`echo "$1/$2" | bc`
	# If there is any remainder...
	
	if (( `echo  "($1%$2) > 0" | bc` ==1 )); then
		# rount up to the next integer
		ceilingResult=$((ceilingResult+1))
	fi
}

setupConfsDir=$1
cd $MY_HADOOP_HOME
export HADOOP_CONFIGURATION_DIR="$MY_HADOOP_HOME/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH"
hadoopVersion=`echo $(basename $MY_HADOOP_HOME) | sed s/[.]/_/g`
if [ -z "$hadoopVersion" ];then
	hadoopVersion="unknown-hadoop-version"
fi

echo "$echoPrefix: VERSION:" $hadoopVersion

source $setupConfsDir/general.sh

if [ -z "$RES_SERVER" ];then
    export RES_SERVER=$DEFAULT_RES_SERVER
fi

totalTests=$SETUP_TESTS_COUNT
if (($LINE_TO_EXECUTE > -1)) && (($LINE_TO_EXECUTE < $SETUP_TESTS_COUNT));then
	totalTests=$LINE_TO_EXECUTE
fi

echo "$echoPrefix: prepering directory on the collecting-server ($RES_SERVER) to the logs" 
currentResultsDir=$LOCAL_RESULTS_DIR/${LOGS_DIR_NAME}_${CURRENT_DATE}
sudo ssh $RES_SERVER mkdir -p $currentResultsDir
sudo ssh $RES_SERVER chown -R $USER $currentResultsDir

for execName in `ls $setupConfsDir | grep $TEST_DIR_PREFIX`
do
	testDir=$setupConfsDir/$execName
	if [ -f $testDir ];then # skip if its not a folder
		continue
	fi
	
	source $testDir/exports.sh

	echo -e \\n\\n "$echoPrefix: -->>> executing $execName" \\n\\n
		
	echo "------------------------------------------"
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
			cp $testDir/*.xml ${HADOOP_CONFIGURATION_DIR}/
			cp $testDir/masters ${HADOOP_CONFIGURATION_DIR}/
			cp $testDir/slaves ${HADOOP_CONFIGURATION_DIR}/
		fi
		
		host=`head -1 $HADOOP_CONFIGURATION_DIR/slaves`
		host_tail=`[[  $host =~ "-" ]] && echo $host | sed 's/.*-//' || echo lan`
		for host in `cat $HADOOP_CONFIGURATION_DIR/slaves`; do
				if [ $host_tail !=  `[[  $host =~ "-" ]] && echo $host | sed 's/.*-//' || echo lan` ];then
					echo "$echoPrefix: slave\'s hostnames are not matching for the same network interface: `cat $HADOOP_CONFIGURATION_DIR/slaves`" | tee $ERROR_LOG
					exit $EEC1
				fi
		done

		if [ $host_tail == "lan" ];then
			echo "$echoPrefix: slave\'s hostname are not tailed with network interface identifier (hostname-ib , hostname-1g or hostname-ib) hadoop traffic will use LAN interface" | tee $ERROR_LOG
			exit $EEC1
		fi

		if (($UNSPREAD_CONF_FLAG == 0));then
			copyConfFiles $HADOOP_CONFIGURATION_DIR/slaves
		fi
		echo "$echoPrefix: Setting slave.host.name on master"
		echo bash ${SCRIPTS_DIR}/set_hadoop_slave_property.sh --hadoop-conf-dir=${HADOOP_CONFIGURATION_DIR} --host-suffix=${INTERFACE_ENDING}
		bash ${SCRIPTS_DIR}/set_hadoop_slave_property.sh --hadoop-conf-dir=${HADOOP_CONFIGURATION_DIR} --host-suffix=${INTERFACE_ENDING}
		echo "$echoPrefix: Setting slave.host.name on slaves"
		bin/slaves.sh ${SCRIPTS_DIR}/set_hadoop_slave_property.sh --hadoop-conf-dir=${HADOOP_CONFIGURATION_DIR} --host-suffix=${INTERFACE_ENDING}

		if (($FIRST_STARTUP == 1));then
			restartParam=" -restart"
		else
			restartParam=""
		fi
		restartingHadoop $RESTART_HADOOP_MAX_ATTEMPTS $restartParam	
	fi
	
	export LOG_PREFIX=${hadoopVersion}.${execName}.${host_tail}.shuffC${SHUFFLE_PROVIDER}.shuffP${SHUFFLE_CONSUMER}.${clusterNodes}n.${DISKS_COUNT}d.${$}pid
	
	echo "$echoPrefix: #slaves=$clusterNodes"
	echo "$echoPrefix: #spindles=$DISKS_COUNT"
	echo "$echoPrefix: LOG_PREFIX=$LOG_PREFIX"
	details="${EXEC_DIR_PREFIX}${execName}"
	totalClusterRam=$((SLAVES_COUNT*RAM_SIZE))
	#totalClusterRam=`echo "scale=0; $RAM_SIZE*$SLAVES_COUNT" | bc`
	case $PROGRAM in
		terasort|sort|wordcount	)
				# calculating the datasize of the input data that going to be generated and the count of it
			DataSetCalculated=$DATA_SET
			if [[ $DATA_SET_TYPE == "node" ]];then
				#DataSetCalculated=$((DATA_SET*SLAVES_COUNT))
				DataSetCalculated=`echo "$DATA_SET * $SLAVES_COUNT *1.0" | bc`
				if (( `echo "$DataSetCalculated < 1" | bc` == 1 )); then
					DataSetCalculated="0${DataSetCalculated}"
				fi	
			fi

			ceilingDivide $totalClusterRam $DataSetCalculated 
			generateDataCount=`echo "$ceilingResult+1" | bc`
			#generateDataCount=$((ceilingResult+1))
				
			export FINAL_DATA_SET=$DataSetCalculated
			export GENERATE_COUNT=$generateDataCount
			export DATA_LABEL="${FINAL_DATA_SET}G"
			if [[ $PROGRAM == "terasort" ]];then
				currentExecDir=$currentResultsDir/$TERASORT_JOBS_DIR_NAME/$details
				outputDir=$TERASORT_DIR
			elif [[ $PROGRAM == "sort" ]];then
				currentExecDir=$currentResultsDir/$SORT_JOBS_DIR_NAME/$details
				outputDir=$SORT_DIR
			else
				currentExecDir=$currentResultsDir/$WORDCOUNT_JOBS_DIR_NAME/$details
				outputDir=$WORDCOUNT_DIR
			fi
			echo "$echoPrefix: running $PROGRAM"
			bash ${SCRIPTS_DIR}/sortcountRunner.sh $currentExecDir $outputDir
		;;
		"TestDFSIO"	) 
			export FINAL_DATA_SET=$totalClusterRam
			export GENERATE_COUNT=1
			export DATA_LABEL="${FINAL_DATA_SET}G"
			currentExecDir=$currentResultsDir/$TEST_DFSIO_JOBS_DIR_NAME/$details
			echo "echoPrefix: running TestDFSIO"
			bash ${SCRIPTS_DIR}/testDFSIORunner.sh $currentExecDir
		;;	
		"pi"		) 
			currentExecDir=$currentResultsDir/$PI_JOBS_DIR_NAME/$details
			echo "echoPrefix: running TestDFSIO"
			bash ${SCRIPTS_DIR}/piRunner.sh $currentExecDir
		;;	
		*			) 
			echo "$echoPrefix: unknown program was selected ($PROGRAM)" | tee $ERROR_LOG
			exit $EEC1
		;;	
	esac
	
	# getting the data set for the report
	#for i in $TOTAL_DATA_SET
	#do
	#	reportDataSet=$i
	#	break # only one iteration needed
	#done
	
	testLogExports=$currentExecDir/testLogExports.sh
	cat $testDir/exports.sh > $testLogExports
	echo "
		export tslDATA_SET='$FINAL_DATA_SET'
		export tslSAMPLES='$NSAMPLES'
	" >> $testLogExports
	
	echo -e \\n\\n\\n\\n\\n
	echo "$echoPrefix: finished test $execName"
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
	export RES_SERVER=$RES_SERVER
" > $TMP_DIR/executeExports.sh
