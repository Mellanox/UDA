#!/bin/bash

concatenateVarsToSpaceSeparatedPathes ()
{
	local beforeStr=$1
	local spaceSeparatedStrs="$2"
	local afterStr=$3
	
	local localPathes=""
	for relDir in $spaceSeparatedStrs;do
		localPathes="$localPathes $beforeStr/$relDir/$afterStr"
	done
	retPathes="$localPathes"
}

getMSLocalLogs()
{
	local pathes="$1"
	local masterDir="$2"
	local slaveDir="$3"
	
	for path in $pathes;do
		echo "$echoPrefix: scp -r $path/* $RES_SERVER:${masterDir} > $DEV_NULL_PATH"
		scp -r $path/* $RES_SERVER:$masterDir > $DEV_NULL_PATH
		echo "$echoPrefix: $EXEC_SLAVES scp -r $path/\* $RES_SERVER:${slaveDir} > $DEV_NULL_PATH"
		$EXEC_SLAVES scp -r $path/\* $RES_SERVER:$slaveDir > $DEV_NULL_PATH
	done
}

getDfsLogs ()
{
	local dfsLogDirs="$1"
	local criteria="$2"
	local masterDir="$3"
	local slaveDir="$4"
	
	for logDir in $dfsLogDirs;
	do
		for slave in $RELEVANT_SLAVES_BY_SPACES;
		do
			fullLogDir=$logDir
			if [[ -n $criteria ]];then
				fullLogDir=`ssh $slave find $logDir -type d -name $criteria`
				if [[ -z $fullLogDir ]];then
					continue
				fi
			fi

			scp -r $slave:$fullLogDir $RES_SERVER:$slaveDir > $DEV_NULL_PATH
			if (($? == 0));then
				sudo rm -rf $fullLogDir
			else
				echo "$echoPrefix: FAILED COPYING $slave:$fullLogDir to $RES_SERVER:$slaveDir"
			fi
		done
	done
}

getNfsAndMasterLocalData ()
{
	local dest=$1
	local dataDirs="$2"
	
	for dataDir in $dataDirs;do
		echo "$echoPrefix: scp -r $dataDir $RES_SERVER:$dest > $DEV_NULL_PATH"
		scp -r $dataDir $RES_SERVER:$dest > $DEV_NULL_PATH
	done
}

collectDir=$1
localDir=$2
applicationId=$3

masterLogsDir=$collectDir/${MASTER_DIR_NAME_PREFIX}\`hostname\`
ssh $RES_SERVER mkdir -p $masterLogsDir
slaveLogsDirPrefix=$collectDir/$SLAVE_DIR_NAME_PREFIX
$EXEC_SLAVES ssh $RES_SERVER mkdir -p ${slaveLogsDirPrefix}\`hostname\`

# getting logs locally from master and slaves
concatenateVarsToSpaceSeparatedPathes $MY_HADOOP_HOME "$HADOOP_LOGS_RELATIVE_DIR" ""
getMSLocalLogs "$retPathes" $masterLogsDir ${slaveLogsDirPrefix}\`hostname\`
getMSLocalLogs "$localDir" $collectDir $collectDir

# getting logs from dfs
getDfsLogs "$DFS_DIR_FOR_LOGS_COLLECTION" $applicationId $masterLogsDir ${slaveLogsDirPrefix}\`hostname\`

# getting logs from nfs and locally from master's regression data
getNfsAndMasterLocalData $collectDir $HADOOP_CONF_DIR

<<COMM
sudo scp $MY_HADOOP_HOME/hs_err_pid* $RES_SERVER:$collectDir/
if (($?==0));then
	rm -f $MY_HADOOP_HOME/hs_err_pid*
fi
echo "$echoPrefix: $EXEC_SLAVES scp -r $localDir/\* $RES_SERVER:$collectDir/"
sudo $EXEC_SLAVES scp $MY_HADOOP_HOME/hs_err_pid\* $RES_SERVER:$collectDir/\;if \(\($?==0\)\)\;then rm -f $MY_HADOOP_HOME/hs_err_pid\*\;fi
COMM

sudo ssh $RES_SERVER chown -R $USER $collectDir
echo "$echoPrefix: finished collecting logs and statistics"

#combine all the node's dstat to one file at cluster level
ssh $RES_SERVER cat $collectDir/\*${DSTAT_LOCAL_FILE_NAME} \| sort \| $SCRIPTS_DIR/reduce-dstat.awk \> $collectDir/$DSTAT_AGGRIGATED_FILE_NAME

pdsh -w $RELEVANT_MACHINES_BY_COMMAS rm -rf $localDir
