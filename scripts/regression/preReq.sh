#!/bin/bash

# Written by: Elad Itzhakian
# Usage: 	./preReq.sh [OPTION]
# Options:	-r	check RAM usage
#			-l	check local log dir free space
#			-n	check NFS log dir free space
#			-c	check CPU usage
#			-w	check if swap is off
#			-b	check base dir free space
#			-i	check base dir initial free space
#			-p	check directory permissions (mapred_local_dir, dfs_data_dir, dfs_name_dir, hadoop_tmp_dir)
#			-h	check HDFS free space
# If errors found, exits with 1, otherwise exits with 0
#
# * Note that this script uses exports from preReqConfiguration.sh *

checkFinish()
{
	local errorFlag=$1
	
	if (($errorFlag==0));then
		echo "$echoPrefix: ~~~ Check passed ~~~"
	else
		echo "$echoPrefix: ~~~ Check ${bold}FAILED${normal} ~~~"
		exit $EEC3
	fi
}

checkBaseFreeSpaceInit()
{
	setVarValue $MASTER_INITTIAL_BASE_FREE_SPACE $DEFAULT_MASTER_INITTIAL_BASE_FREE_SPACE
	MASTER_INITTIAL_BASE_FREE_SPACE=$retVal_setVarValue
	
	echo "$echoPrefix: ~~~ Checking initial free space on base partition on master ~~~"
	checkSpaceOnDir `hostname` $BASE_DIR $MASTER_INITTIAL_BASE_FREE_SPACE "LOCAL"
	checkFinish $retVal_checkSpaceOnDir
}

checkBaseFreeSpace()
{
	setVarValue $MACHINE_BASE_FREE_MIN_SPACE $DEFAULT_MACHINE_BASE_FREE_MIN_SPACE
	MACHINE_BASE_FREE_MIN_SPACE=$retVal_setVarValue # 1GB default value
	local errorFlag=0
	echo "$echoPrefix: ~~~ Checking free space on base partition master & slaves ~~~"
	for machine in $MASTER $SLAVES_BY_SPACES
	do
		checkSpaceOnDir $machine $BASE_DIR $MACHINE_BASE_FREE_MIN_SPACE "LOCAL"
		errorFlag=$((errorFlag+retVal_checkSpaceOnDir))
	done	
	checkFinish $errorFlag	
}

checkNfsLoggerSpace()
{
	setVarValue $NFS_LOG_DIR_MIN_SPACE $DEFAULT_NFS_LOG_DIR_MIN_SPACE
	NFS_LOG_DIR_MIN_SPACE=$retVal_setVarValue

	echo "$echoPrefix:  ~~~ Checking minimal disk space on NFS log dir ~~~"
	echo "$echoPrefix:  checking $NFS_RESULTS_DIR"
	checkSpaceOnDir `hostname` $NFS_RESULTS_DIR $NFS_LOG_DIR_MIN_SPACE "NFS"
	checkFinish $retVal_checkSpaceOnDir
}

checkLocalLoggerSpace()
{
	setVarValue $LOCAL_LOG_DIR_MIN_SPACE $DEFAULT_LOCAL_LOG_DIR_MIN_SPACE
	LOCAL_LOG_DIR_MIN_SPACE=$retVal_setVarValue

	echo "$echoPrefix: ~~~ Checking minimal disk space on local log dir ~~~"
	echo "$echoPrefix:  checking $RES_SERVER:$LOCAL_RESULTS_DIR"
	checkSpaceOnDir $RES_SERVER $LOCAL_RESULTS_DIR $LOCAL_LOG_DIR_MIN_SPACE "LOCAL"
	checkFinish $retVal_checkSpaceOnDir
}

checkSwapoff()
{
	local errorFlag=0
	echo "$echoPrefix: ~~~ Checking swap is off ~~~"
	for machine in $MASTER $SLAVES_BY_SPACES
	do
		swapStatus=`ssh -t $machine $SWAPON_PATH -s | grep /`
		if [ -n "$swapStatus" ]; then
			echo "$echoPrefix: ${bold}ERROR:${normal} Please turn swap off on $machine using sudo swapoff -a"
			errorFlag=1
		fi
	done
	
	checkFinish $errorFlag	
}

checkPermissionsOnMachineDir()
{
	local machine=$1
	local i=$2
	local errorFlag=0
	echo "$echoPrefix: checking directory $i on $machine"
	echo "$echoPrefix: ssh $machine ls -ld $i | grep -c $i" # Added for debugging purposes
	dirExists=`ssh $machine ls -ld $i | grep -c $i`
	if (($dirExists!=1)); then
		echo "$echoPrefix: ${bold}ERROR:${normal} No such folder $i on $machine - Exiting"
		errorFlag=1
	else
		currentDirOutput=`ssh $machine ls -ld $i`
		local attempt=0
		while [[ -z "$currentDirOutput" ]] && (($attempt < $SSH_MAX_ATTEMPTS));
                do
                        attempt=$((attempt+1))
                	currentDirOutput=`ssh $machine ls -ld $i`
		done
		
		currentDirPermissions=`echo "$currentDirOutput" | cut --delimiter=" " -f 1`
		currentDirOwner=`echo "$currentDirOutput" | cut --delimiter=" " -f 3`
		othersPermissions=`echo "$currentDirPermissions" | cut -c 8-10`
		ownerPermissions=`echo "$currentDirPermissions" | cut -c 2-4`
		groupPermissions=`echo "$currentDirPermissions" | cut -c 5-7`
		checkIfUserInGroup $i
		if [[ -z "$currentDirOutput" ]]; then
			errorFlag=1
			echo "$echoPrefix: ${bold}ERROR:${normal} Could not retrieve dir permission info."
		elif [ "$currentDirOwner" == "$USER" ]; then
			if [ "$ownerPermissions" != "$OWNER_PERMISSIONS" ]; then
				echo "$echoPrefix: ${bold}ERROR:${normal} $USER is owner of $i but has insufficient permissions."
				errorFlag=1
			else
				errorFlag=0
			fi
		else
			echo "$echoPrefix: ${bold}ERROR:${normal} $USER needs to be owner of dir $i"
			errorFlag=1
		fi
	fi
	retVal_checkPermissionsOnMachine=$errorFlag
}

checkIfUserInGroup()
{
	userGroupsArr=`id -G`
	local dir=$1
	dirGroup=`ssh $machine ls -ldn $dir | awk '{print $4}'`
	local attempt=0
        while [[ -z "$dirGroup" ]] && (($attempt < $SSH_MAX_ATTEMPTS));
        do
                attempt=$((attempt+1))
        	dirGroup=`ssh $machine ls -ldn $dir | awk '{print $4}'`
	done	
	retVal_UserInGroup="0"
	for j in $userGroupsArr; do
		if [ "$retVal_UserInGroup" == "0" ] && [ "$dirGroup" == "$j" ]; then
			retVal_UserInGroup=1
		fi
	done
}

checkPermissions()
{
	local errorFlag=0

	echo "$echoPrefix: ~~~ Checking permissions on Hadoop & HDFS directories ~~~"
	
	for i in {$HADOOP_TMP_DIR_BY_SPACES,$DFS_NAME_DIR_BY_SPACES};do
		checkPermissionsOnMachineDir "$MASTER" "$i"
		errorFlag=$((errorFlag+retVal_checkPermissionsOnMachine));
	done
	
	for s in $SLAVES_BY_SPACES
	do
		for i in {$MAPRED_LOCAL_DIR_BY_SPACES,$DFS_DATA_DIR_BY_SPACES};do
			checkPermissionsOnMachineDir "$s" "$i"
			errorFlag=$((errorFlag+retVal_checkPermissionsOnMachine));
		done
	done
	
	checkFinish $errorFlag
}

checkSpaceOnDir()
{
	local machine=$1
	local directories=$2
	local threshold=$3
	local dirsType=$4
	local errorFlag=0
	
	if [[ $dirsType == "NFS" ]]; then
		fieldIndex=3
	else
		fieldIndex=4
	fi
	
	for i in $directories
	do
		echo "$echoPrefix: checking directory $i on $machine"
		currentDiskSpace=`ssh $machine df $DF_BLOCKSIZE_SCALE $i | grep / | awk -v ind=$fieldIndex '{print $ind}'`
		local attempt=0
                while [[ -z "$currentDiskSpace" ]] && (($attempt < $SSH_MAX_ATTEMPTS));
                do
                        attempt=$((attempt+1))
                        currentDiskSpace=`ssh $machine df $DF_BLOCKSIZE_SCALE $i | grep / | awk -v ind=$fieldIndex '{print $ind}'`
                done
		
		if [[ -z "$currentDiskSpace" ]]; then
			errorFlag=1
			echo "$echoPrefix: ${bold}ERROR:${normal} Could not retrieve diskspace from $machine"
		elif (($currentDiskSpace<$threshold)); then
			errorFlag=1
			echo "$echoPrefix: ${bold}ERROR:${normal} Not enough space on $machine on dir $i. Need $threshold got $currentDiskSpace"
		fi
	done
	
	retVal_checkSpaceOnDir=$errorFlag
}

setDirsValues()
{
	setVarValue $MAPRED_LOCAL_DIR_MIN_SPACE $DEFAULT_MAPRED_LOCAL_DIR_MIN_SPACE
	MAPRED_LOCAL_DIR_MIN_SPACE=$retVal_setVarValue # 2GB default value

	setVarValue $HADOOP_TMP_DIR_MIN_SPACE $DEFAULT_HADOOP_TMP_DIR_MIN_SPACE
	HADOOP_TMP_DIR_MIN_SPACE=$retVal_setVarValue # 2GB default value

	setVarValue $DFS_NAME_DIR_MIN_SPACE $DEFAULT_DFS_NAME_DIR_MIN_SPACE
	DFS_NAME_DIR_MIN_SPACE=$retVal_setVarValue # 2GB default value

	setVarValue $DFS_DATA_DIR_MIN_SPACE $DEFAULT_DFS_DATA_DIR_MIN_SPACE
	DFS_DATA_DIR_MIN_SPACE=$retVal_setVarValue

	setVarValue $MASTER_DFS_DIRS_MIN_SPACE $DEFAULT_MASTER_DFS_DIRS_MIN_SPACE
	MASTER_DFS_DIRS_MIN_SPACE=$retVal_setVarValue

	if [[ -z "$DFS_DATA_DIR_BY_SPACES" ]]; then
		DFS_DATA_DIR_BY_SPACES=$DFS_DATANODE_DATA_DIR_BY_SPACES
	fi
	
	if [[ -z "$MAPRED_LOCAL_DIR_BY_SPACES" ]]; then
		MAPRED_LOCAL_DIR_BY_SPACES=$MAPREDUCE_CLUSTER_LOCAL_DIR_BY_SPACES
	fi

	if [[ -z "$DFS_NAME_DIR_BY_SPACES" ]]; then
		DFS_NAME_DIR_BY_SPACES=$DFS_NAMENODE_NAME_DIR_BY_SPACES
	fi
}

checkHdfsSpace()
{
	setDirsValues

	local errorFlag=0

	echo "$echoPrefix: ~~~ Checking minimal disk space on hdfs directories ~~~"
	
	checkSpaceOnDir "$MASTER" "$MASTER_DFS_DIRS_BY_SPACES" "$MASTER_DFS_DIRS_MIN_SPACE"
	errorFlag=$((errorFlag+retVal_checkSpaceOnDir))
	
	#checkSpaceOnDir "$MASTER" "$HADOOP_TMP_DIR_BY_SPACES" "$HADOOP_TMP_DIR_MIN_SPACE"
	#errorFlag=$((errorFlag+retVal_checkSpaceOnDir))
	
	#checkSpaceOnDir "$MASTER" "$DFS_NAME_DIR_BY_SPACES" "$DFS_NAME_DIR_MIN_SPACE"
	#errorFlag=$((errorFlag+retVal_checkSpaceOnDir))

	for s in $SLAVES_BY_SPACES
	do
		checkSpaceOnDir "$s" "$MAPRED_LOCAL_DIR_BY_SPACES" "$MAPRED_LOCAL_DIR_MIN_SPACE"
		errorFlag=$((errorFlag+retVal_checkSpaceOnDir))
		
		checkSpaceOnDir "$s" "$DFS_DATA_DIR_BY_SPACES" "$DFS_DATA_DIR_MIN_SPACE"
		errorFlag=$((errorFlag+retVal_checkSpaceOnDir))
	done
	
	checkFinish $errorFlag	
}

checkRamUsage()
{

	## Minimum RAM value (Get in MB from user, NEED TO CONVERT TO KILOBYTES)
	setVarValue $MIN_RAM_REQUIRED $DEFAULT_MIN_RAM_REQUIRED
	MIN_RAM_REQUIRED=$retVal_setVarValue # 16GB default value

	## Conversion from MB to KB
	MIN_RAM_REQUIRED=$(($MIN_RAM_REQUIRED*1024))
	
	local errorFlag=0
	
	for s in $SLAVES_BY_SPACES
	do
		echo "$echoPrefix: ~~~ Checking free RAM on $s"
		availableRam=`ssh $s cat /proc/meminfo | grep MemFree | awk '{print $2}'` # Get available ram in KB
		local attempt=0
		while [[ -z "$availableRam" ]] && (($attempt < $SSH_MAX_ATTEMPTS));
                do
                       attempt=$((attempt+1))
	               availableRam=`ssh $s cat /proc/meminfo | grep MemFree | awk '{print $2}'`
	
		if  [[ -z "$availableRam" ]]; then
			echo "$echoPrefix: ${bold}ERROR:${normal} Could not retrieve free memory from $s"
			errorFlag=1
		elif (( $availableRam<$MIN_RAM_REQUIRED )); then
			echo "$echoPrefix: ${bold}ERROR:${normal} Not enough free RAM on $s -  Need at least $MIN_RAM_REQUIRED KB but got only $availableRam KB"
			errorFlag=1
		else
			echo "$echoPrefix:RAM check OK on $s"
		fi
		done
	done
	
	checkFinish $errorFlag
}

checkCpuUsage()
{

	## Max CPU Usage = (0<p<1)
	setVarValue $MAX_CPU_USAGE $DEFAULT_MAX_CPU_USAGE
	MAX_CPU_USAGE=$retVal_setVarValue # 0.2 default value
	echo "$echoPrefix: ~~~ Checking CPU Usage (average of 5 samples)"
	local errorFlag=0
	for s in $SLAVES_BY_SPACES
	do
		CPU="0"
		for i in {1..$CPU_USAGE_SAMPLES_TO_AVERAGE_COUNT};
		do
			CPUTMP=`ssh $s /usr/bin/top -b -n1 | grep "Cpu(s)" | awk '{ split($5,a,"%") ; print (100-a[1])/100'}`
	                local attempt=0
	                while [[ -z "$CPUTMP" ]] && (($attempt < $SSH_MAX_ATTEMPTS));
        	        do
                	        attempt=$((attempt+1))
	                	CPUTMP=`ssh $s /usr/bin/top -b -n1 | grep "Cpu(s)" | awk '{ split($5,a,"%") ; print (100-a[1])/100'}`
			done
			if [[ -z "$CPUTMP" ]]; then
				echo "$echoPrefix: ${bold}ERROR:${normal} Could not retrieve CPU usage on $s"
				errorFlag=1
			fi
			CPU=$(awk -v n1="$CPU" -v n2="$CPUTMP" 'BEGIN{print n1+n2}')
		done
		CPU=$(awk -v n1="$CPU" 'BEGIN{print n1/5}')
		CPU_CMP=$(awk -v n1="$CPU" -v n2="$MAX_CPU_USAGE" 'BEGIN{print (n1>n2)?1:0 }')
		echo "$echoPrefix: CPU usage on $s is $CPU"
		if [ "$CPU_CMP" -eq 1 ] ; then
			echo "$echoPrefix: ${bold}ERROR:${normal} CPU on $s Exceeds $MAX_CPU_USAGE"
			errorFlag=1
		fi
	done
	checkFinish $errorFlag
}

checkInodes()
{
	setDirsValues
	echo "$echoPrefix: ~~~ Checking INODES ~~~"
	local errorFlag=0
	local ALL="$MASTER $SLAVES_BY_SPACES"
	for j in $ALL
	do
		for i in {$HADOOP_TMP_DIR_BY_SPACES,$DFS_NAME_DIR_BY_SPACES,$MAPRED_LOCAL_DIR_BY_SPACES,$DFS_DATA_DIR_BY_SPACES}
		do
			currentInodesRatio=`ssh $j df -i $i | tail -1 | awk -v def=$DEFAULT_MIN_INODES_PERCENT '{ print ((100-$5)<def)?1:0 }'`
			local attempt=0
			while [[ -z "$currentInodesRatio" ]] && (($attempt < $SSH_MAX_ATTEMPTS));
                        do
                                attempt=$((attempt+1))
                        	currentInodesRatio=`ssh $j df -i $i | tail -1 | awk -v def=$DEFAULT_MIN_INODES_PERCENT '{ print ((100-$5)<def)?1:0 }'`
			done	
			if [[ -z "$currentInodesRatio" ]]; then
				echo "$echoPrefix: ${bold}ERROR:${normal} Could not retrieve current inodes ratio on $j"
			elif [ "$currentInodesRatio" == "1" ]; then
				echo "$echoPrefix: ${bold}ERROR:${normal} Not enough free INODES on dir $i on slave $j"
				errorFlag=1
			fi
		done
	done
	checkFinish $errorFlag
}

setVarValue()
{
	local property=$1
	local default=$2
	if [ -z "$property" ]; then
		if [ -z "$default" ]; then
			echo "$echoPrefix: function setVarValue() failed - both property and default value are not set."
			exit $EEC3
		else
			retVal_setVarValue=$default
		fi
	else
		retVal_setVarValue=$property
	fi
}

# Default values
bold=`tput bold`
normal=`tput sgr0`

echoPrefix=`eval $ECHO_PATTERN`

ramFlag=0
localLoggersSpaceFlag=0
nfsLoggersSpaceFlag=0
cpuFlag=0
swapoffFlag=0
osFreeSpaceFlag=0
osFreeSpaceMasterInitFlag=0
permissionsFlag=0
hdfsSpaceFlag=0


while getopts ":rlncwbiphd" Option
do
	case ${Option} in
			"r"	) checkRamUsage ;; #ramFlag=1 ;;
			"l"	) checkLocalLoggerSpace ;; #localLoggersSpaceFlag=1 ;; 
			"n"	) checkNfsLoggerSpace ;; #nfsLoggersSpaceFlag=1 ;;
			"c"	) checkCpuUsage ;; #cpuFlag=1 ;; 
			"w"	) checkSwapoff ;; #swapoffFlag=1 ;; 
			"b"	) checkBaseFreeSpace ;; #baseFreeSpaceFlag=1 ;;
			"i"	) checkBaseFreeSpaceInit ;; # baseFreeSpaceMasterInitFlag=1 ;;
			"p"	) checkPermissions ;; #permissionsFlag=1 ;; 
			"h"	) checkHdfsSpace ;; #hdfsSpaceFlag=1 ;;
			"d" 	) checkInodes ;; 
			*	) echo "$echoPrefix: wrong input" ;  exit $SEC ;;   # Default.
	esac
done
