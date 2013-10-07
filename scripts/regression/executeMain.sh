#!/bin/sh
echoPrefix=`eval $ECHO_PATTERN`

errorHandler()
{
	# there is a scenario that error occured but the return value will be 0 - 
	# when start_hadoopExcel.sh or mkteragenExcel.sh prints their usage-print,
	# (which it a unsuccessfull scenario for this script's purposes).
	# in such case this script won't recognized the problem
    if (($1==1));then
		echo "$echoPrefix: $2" | tee $ERROR_LOG
        exit $EEC1
	fi
}

restartingHadoop()
{
	echo "$echoPrefix: restarting Hadoop"
	bash $SCRIPTS_DIR/start_hadoopExcel.sh $@ 
	if (($?==1));then
		echo "$echoPrefix: failed to restart Hadoop" | tee $ERROR_LOG
        exit $EEC1
	fi
}

copyConfFiles()
{
	echo "$echoPrefix: Copy conf dir to slaves"
	for slave in `cat $1`; do

	# Elad: this is a temporary fix, waiting for interfaces to come back up after openibd restart.
	#	The permanent fix should be in setupTestMain.sh where after restarting openibd on all
	# 	slaves, we wait until they all return.
		copycount=0
		scp -r $HADOOP_CONF_DIR/* $slave:$HADOOP_CONF_DIR > $DEV_NULL_PATH
		while [ $? -eq 1 ] && [ $copycount -lt 10 ];
		do
			echo "Failed to copy conf files to $slave, trying again in 5 seconds"
			sleep 5
			copycount=$[$copycount+1]
			scp -r $HADOOP_CONF_DIR/* $slave:$HADOOP_CONF_DIR > $DEV_NULL_PATH
		done
		if (($?==1));then
			echo "$echoPrefix: failed to copy conf files to $slave after 10 attempts - assuming node is down" | tee $ERROR_LOG
			exit $EEC1
		fi
	done
}

calculeteDataSetSize()
{
	local dataSetCalculated=$DATA_SET
	if [[ $DATA_SET_TYPE == "node" ]];then
		dataSetCalculated=`echo "$DATA_SET * $SLAVES_COUNT * 1.0" | bc`
		if (( `echo "$dataSetCalculated < 1" | bc` == 1 )); then
			dataSetCalculated="0${dataSetCalculated}"
		fi	
	fi
	calculeteDataSetSizeRetVal=$dataSetCalculated
}

ceilingDivide() 
{
	# Normal integer divide.
	#ceilingResult=$(($1/$2))
	local ceilingResult=`echo "$1/$2" | bc`
	# If there is any remainder...
	
	if (( `echo  "($1%$2) > 0" | bc` ==1 )); then
		# rount up to the next integer
		ceilingResult=$((ceilingResult+1))
	fi
	
	ceilingDivideRetVal=$ceilingResult
}

calculateDataCount()
{
	local clusterRam=$1
	local ds=$2
	#local generateDataCount=1
	#if ((`echo "${clusterRam} >= ${ds}" | bc` == 1));then
	#	ceilingDivide $clusterRam $ds
	#	generateDataCount=`echo "$ceilingDivideRetVal+1" | bc`
	#fi
	
	local cacheFlushingDataSize=0
	local generateDataCount=1
	if ((`echo "${clusterRam} <= ${ds}" | bc` == 1));then
		cacheFlushingDataSize=$clusterRam
	elif ((`echo "${clusterRam}/2 >= ${ds}" | bc` == 1));then
		ceilingDivide $clusterRam $ds
		generateDataCount=`echo "$ceilingDivideRetVal+1" | bc`
	else # ((`echo "${clusterRam} > ${ds}" | bc` == 1)) && ((`echo "${clusterRam}/2 < ${ds}" | bc` == 1)), assuming $clusterRam is positive
		generateDataCount=2
		cacheFlushingDataSize=`echo "${clusterRam} - ${ds}" | bc`
	fi
	export CACHE_FLUSHING_DATA_SIZE=$cacheFlushingDataSize
	export CACHE_FLUSHING_COUNT="${CACHE_FLUSHING_DATA_SIZE}G"
	
	calculateDataCountRetVal=$generateDataCount
}

getJarExplicitName()
{
	exportName=$1
	eval jarName=\$$exportName # getting the value of the variable with "inside" successCriteria
	echo "JAR NAME IS: "$jarName
	explicitJarName=""
	for i in `echo $jarName`;do
		explicitJarName="$i"
		break
	done
	if [[ -z $explicitJarName ]];then
		echo "$echoPrefix: there are no examples-jar in $MY_HADOOP_HOME" | tee $ERROR_LOG
		exit $EEC1
	fi
	
	export `echo $exportName`$EXPLICIT_JAR_SUFFIX="${JAR_FILE_RELATIVE_DIR}${explicitJarName}"
}

manageDataGenerationInfo()
{
	calculeteDataSetSize # calculating the datasize of the input data that going to be generated and the count of it
	export FINAL_DATA_SET=$calculeteDataSetSizeRetVal
	if (($CACHE_FLUHSING == 1));then
		totalClusterRam=$((SLAVES_COUNT*RAM_SIZE))
		calculateDataCount $totalClusterRam $calculeteDataSetSizeRetVal
		export GENERATE_COUNT=$calculateDataCountRetVal
	else
		export GENERATE_COUNT=1
	fi
}

setupConfsDir=$1
#export $MY_HADOOP_HOME=$MY_HADOOP_HOME/$HADOOP_HOME_RELATIVE_DIR
cd $MY_HADOOP_HOME


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
currentResultsDir=$LOCAL_RESULTS_DIR/${LOGS_DIR_NAME}_${ENV_FIXED_NAME}_${CURRENT_DATE}
sudo ssh $RES_SERVER mkdir -p $currentResultsDir
sudo ssh $RES_SERVER chown -R $USER $currentResultsDir

echo "
	export terasortLAST_DATASET_NUM=0
	export sortLAST_DATASET_NUM=0
	export wordcountLAST_DATASET_NUM=0
	" > $TMP_DIR/sortcountRunnerExports.sh

for execName in `ls $setupConfsDir | grep $TEST_DIR_PREFIX`
do
	testDir=$setupConfsDir/$execName
	if [ -f $testDir ];then # skip if its not a folder
		continue
	fi
	
	source $testDir/exports.sh
	source $testDir/preReqTest.sh

	echo "------------------------------------------"
	echo -e \\n\\n "$echoPrefix: -->>> executing $execName" \\n\\n
	echo "------------------------------------------"
				
	if (($RESTART_HADOOP==1))
	then
		if (($UNSPREAD_CONF_FLAG == 0));then
			cp $testDir/*.xml ${HADOOP_CONF_DIR}/
			cp $testDir/masters ${HADOOP_CONF_DIR}/
			cp $testDir/slaves ${HADOOP_CONF_DIR}/
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
		
		#if (($FIRST_STARTUP == 1)) && (($SAVE_HDFS_FLAG == 0));then
		if (($FORCE_DFS_FORMAT)) ||  (($FIRST_STARTUP && ! $SAVE_HDFS_FLAG));then
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

	getJarExplicitName "HADOOP_EXAMPLES_JAR"
	getJarExplicitName "HADOOP_TEST_JAR"
	getJarExplicitName "CMD_JAR"
	
	case $PROGRAM in
		terasort|sort|wordcount	)
			manageDataGenerationInfo
			source $TMP_DIR/sortcountRunnerExports.sh
			export CURRENT_DATA_COUNT="${FINAL_DATA_SET}G"
			if [[ $PROGRAM == "terasort" ]];then
				currentExecDir=$currentResultsDir/$TERASORT_JOBS_DIR_NAME/$details
				outputDir=$TERASORT_DIR
				lastDatasetNum=$terasortLAST_DATASET_NUM
			elif [[ $PROGRAM == "sort" ]];then
				currentExecDir=$currentResultsDir/$SORT_JOBS_DIR_NAME/$details
				outputDir=$SORT_DIR
				lastDatasetNum=$sortLAST_DATASET_NUM
			else
				currentExecDir=$currentResultsDir/$WORDCOUNT_JOBS_DIR_NAME/$details
				outputDir=$WORDCOUNT_DIR
				lastDatasetNum=$wordcountLAST_DATASET_NUM
			fi
			
			echo "$echoPrefix: running $PROGRAM"
			bash ${SCRIPTS_DIR}/sortcountRunner.sh $currentExecDir $outputDir $lastDatasetNum
			runnerStatus=$?
		;;
		"TestDFSIO"	) 
			manageDataGenerationInfo
			#export FINAL_DATA_SET=$totalClusterRam
			#export GENERATE_COUNT=1
			#export DATA_LABEL="${FINAL_DATA_SET}G"
			currentExecDir=$currentResultsDir/$TEST_DFSIO_JOBS_DIR_NAME/$details
			echo "$echoPrefix: running TestDFSIO"
			bash ${SCRIPTS_DIR}/testDFSIORunner.sh $currentExecDir
			runnerStatus=$?
		;;	
		"pi"		) 
			currentExecDir=$currentResultsDir/$PI_JOBS_DIR_NAME/$details
			echo "$echoPrefix: running pi"
			bash ${SCRIPTS_DIR}/piRunner.sh $currentExecDir
			runnerStatus=$?
		;;	
		*			) 
			echo "$echoPrefix: unknown program was selected ($PROGRAM)" | tee $ERROR_LOG
			exit $EEC1
		;;	
	esac
	echo runnerStatus IS: $runnerStatus
	
	### for preReq purposes
	unset PRE_REQ_TEST_FLAGS
	###
	
	testLogExports=$currentExecDir/testLogExports.sh
	cat $testDir/exports.sh > $testLogExports
	echo "
		export tslDATA_SET='$FINAL_DATA_SET'
		export tslSAMPLES='$NSAMPLES'
	" >> $testLogExports
	
	if (($runnerStatus == $EEC2));then
		echo "$echoPrefix: error occur in the setup on the cluster"
		exit $CEC
	fi
	
	echo -e \\n\\n\\n\\n\\n
	echo "$echoPrefix: finished test $execName"
	echo -e \\n\\n\\n\\n\\n
	
	if (($TEST_RUN_FLAG == 1));then
		echo "$echoPrefix: test-run mode - breaking after one test"
		break
	fi
done

echo "$echoPrefix: stopping all hadoop processes"
eval $DFS_STOP
eval $MAPRED_STOP

echo "
	#!/bin/sh
	export HADOOP_VERSION='$hadoopVersion'
	export CURRENT_LOCAL_RESULTS_DIR='$currentResultsDir'
	export RES_SERVER=$RES_SERVER
	export EXEC_DIR_FOR_VALIDATION='$currentExecDir'
" > $SOURCES_DIR/executeExports.sh
