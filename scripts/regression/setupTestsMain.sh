#!/bin/bash
setLogMtt ()
{
	local node=$1
	showNumMttCmd="cat /sys/module/mlx4_core/parameters/log_num_mtt"
	showMttsPerSegCmd="cat /sys/module/mlx4_core/parameters/log_mtts_per_seg"
	if (($logNumMtt == `eval ssh $node $showNumMttCmd`)) && (($logMttsPerSeg == `eval ssh $node $showMttsPerSegCmd`));then
		echo "$echoPrefix: no need to configure log_num_mtt and log_mtts_per_seg"
		return 0;
	fi
	
	logNumMttFlag=1
	echo "$echoPrefix: setting log_num_mtt and log_mtts_per_seg:"

	echo "$MLX_CONF_OPTIONS_LINE log_num_mtt=$logNumMtt log_mtts_per_seg=$logMttsPerSeg" | sudo ssh $node tee $MOFED_CONF_PATH
	echo "*********"
	sudo ssh $node cat $MOFED_CONF_PATH
	echo "*********"
	
	opensmProcesses=`ssh $node ps -ef | grep "$OPENSM_PROCESS_REGISTRATION" | grep -v "grep"`
	if [[ -n $opensmProcesses ]];then
		opensmPID=`echo $opensmProcesses | awk 'BEGIN{};{print $2}'`
		echo "$echoPrefix: shuting down open sm (PID=$opensmPID)"
		sudo ssh $node kill -9 $opensmPID
	fi
	
	echo "$echoPrefix: restarting open-ibd"
	bash $SCRIPTS_DIR/functionsLib.sh "execute_command" 5 600 "sudo ssh $node $OPENIBD_PATH restart" 
	#bash $SCRIPTS_DIR/commandExecuter.sh "sudo ssh $node $OPENIBD_PATH restart" 5 600
	if (($? != 0));then
		echo "$echoPrefix: failing to restart the open-ibd" | tee $ERROR_LOG
		exit $EEC1
	fi
	
	if [[ -n $opensmProcesses ]];then
		echo "$echoPrefix: starting open sm"
		sudo ssh $node $OPENSM_PATH start
	fi
	
	echo "$echoPrefix: log_num_mtt is `eval ssh $node $showNumMttCmd`, log_mtts_per_seg is `eval ssh $node $showMttsPerSegCmd`"
	
	if (($logNumMtt != `eval ssh $node $showNumMttCmd`)) || (($logMttsPerSeg != `eval ssh $node $showMttsPerSegCmd`));then
		echo "$echoPrefix: the configuration of the mtt parameters failed. check if the files on `dirname $MOFED_CONF_PATH` allready contains those parameters" | tee $ERROR_LOG
		exit $EEC1
	fi
	
	restartClusterConfiguration=1
}

setIbMessage () 
{
	local node=$1
	local ibMessageSize=$2

	local existIbMessagesSize=`ssh $node ps -ef | grep ib_write_bw | grep -v "grep" | awk 'BEGIN{FS="-s"};{print $2}' | awk 'BEGIN{};{print $1}'`
	if [[ -n $existIbMessagesSize ]];then
		if (($ibMessageSize == $existIbMessagesSize));then
			echo "$echoPrefix: proper ib-message is allready exist, there's no need to create a new one"
			return 0;
		fi
		
		local existIbMessagesPID=`ssh $node ps -ef | grep ib_write_bw | grep -v "grep" | awk 'BEGIN{};{print $2}'`
		echo "$echoPrefix: killing the exist ib-message (PID $existIbMessagesPID) "
		sudo ssh $node kill -9 $existIbMessagesPID
		if (($? != 0));then
			echo "$echoPrefix: failing terminating ib_message" | tee $ERROR_LOG
			exit $EEC1
		fi
	fi
	
	if (($ibMessageSize != 0));then
		echo "$echoPrefix: creating ib-message of ${ibMessageSize}Mb"
		local msgSizeInBytes=$((msgSizeInMb*IB_MESSAGE_MULTIPLIER))
		sudo ssh $node "ib_write_bw -s $msgSizeInBytes & sleep 5"
	else
		echo "$echoPrefix: there is no need in ib-message"
	fi
	#ps -ef | grep ib_write_bw | grep -v "grep" | awk 'BEGIN{FS="-s"};{print $2}' | awk 'BEGIN{};{print $1}'
}

setLog4j()
{
	log4jFile=$1
	paramsAndVals=$2
	local tmpLog4j=$TMP_DIR/${LOGGER_NAME}_${TEMP_SUFFIX}
	for paramAndVal in $paramsAndVals;do
		param=`echo $paramAndVal | awk 'BEGIN{FS="="} {print $1}'`
		if ((`grep -c "${param}=" $log4jFile` == 0));then
			echo $paramAndVal >> $log4jFile
		else
			sed "/${param}=/ c $paramAndVal" $log4jFile > $tmpLog4j
			mv $tmpLog4j $log4jFile
		fi
	done
	
	pdsh -w $SLAVES_BY_COMMAS scp $master:$log4jFile $log4jFile 
}

setupConfsDir=$1
echoPrefix=`eval $ECHO_PATTERN`
master=$MASTER
logNumMttFlag=0

source $setupConfsDir/general.sh

rm -rf $TMP_DIR/*
rm -rf $STATUS_DIR/*

logNumMtt=$LOG_NUM_MTT
if [ -z "$logNumMtt" ];then
    logNumMtt=$DEFAULT_LOG_NUM_MTT
fi

logMttsPerSeg=$LOG_MTTS_PER_SEG
if [ -z "$logMttsPerSeg" ];then
    logMttsPerSeg=$DEFAULT_LOG_MTTS_PER_SEG
fi

ibMessageSize=$IB_MESSAGE_SIZE
if [ -z "$ibMessageSize" ];then
    ibMessageSize=$DEFAULT_IB_MESSAGE_SIZE
fi

echo "$echoPrefix: $killing all java processes"
sudo pkill -9 java

setLogMtt $master
loggerFile=$HADOOP_CONF_DIR/$LOGGER_NAME
setLog4j "$loggerFile" "$LOGGER_PARAMS_AND_VALS"

# preparing the slaves
for slave in $SLAVES_BY_SPACES
do
	echo -e \\n\\n
	echo "$echoPrefix: $slave:"

	echo "$echoPrefix: cleaning $TMP_DIR_NAME and $STATUS_DIR_NAME directories"
#bash $SCRIPTS_DIR/safeRemove.sh $echoPrefix "ssh $slave rm -rf $TMP_DIR/\*" $TMP_DIR
	sudo ssh $slave rm -rf $TMP_DIR/\*
	ssh $slave rm -rf $STATUS_DIR/\*
	
	echo "$echoPrefix: killing all java processes"
	sudo ssh $slave pkill -9 java
		
	echo "$echoPrefix: creating the needed directories"
	#sudo ssh $slave mkdir -p $DIRS_TO_CREATE
	#sudo ssh $slave chown -R $USER $DIRS_TO_CREATE
	#sudo ssh $slave chgrp -R $GROUP_NAME $DIRS_TO_CREATE
		
	setLogMtt $slave
	setIbMessage $slave $ibMessageSize
done

if (($logNumMttFlag==1));then
	bash $SCRIPTS_DIR/functionsLib.sh "execute_command" 15 60 "pdsh -w $master,$SLAVES_BY_COMMAS echo" # a way to wait till the ssh ability will recover
	#bash $SCRIPTS_DIR/commandExecuter.sh "pdsh -w $master,$SLAVES_BY_COMMAS echo" 15 60
fi

echo "
	#!/bin/sh
" > $SOURCES_DIR/setupTestsExports.sh
