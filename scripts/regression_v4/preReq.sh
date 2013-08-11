#!/bin/bash

# Checks  minimal requirements before regression starts running tests:
# Permissions on HADOOP_PATHS
# Makes sure swap is OFF
# Free space on HADOOP_PATHS,MAPRED_LOCAL_DIR and DFS_DATA_DIR, and LOG_DIR
# Enough available RAM and CPU usage not too high
# If errors found, exits with 1, otherwise exits with 0

checkFinish()
{
	local errorFlag=$1
	
	if (($errorFlag==0));then
		echo "$echoPrefix: ~~~ Check passed ~~~"
	else
		echo "$echoPrefix: ~~~ Check FAILED ~~~"
		exit $EEC3
	fi
}

checkOsFreeSpaceInit()
{
	local errorFlag=0
	
	echo "$echoPrefix: ~~~ Checking free space on OS partition the master before executing the regression ~~~"	
	freeSpaceMB=`sudo df $DF_BLOCKSIZE_SCALE | grep -m 1 "\% \/" | awk 'BEGIN{}{print $4}'`
	if (($freeSpaceMB < $MASTER_INITTIAL_OS_FREE_SPACE));then
		echo -e "$echoPrefix: there is no enouth place on the master's OS-disk" | tee $ERROR_LOG
		errorFlag=1
	fi
	
	checkFinish $errorFlag
}

checkOsFreeSpace()
{
	local errorFlag=0

	echo "$echoPrefix: ~~~ Checking free space on OS partition master & slaves ~~~"
	for machine in $MASTER $SLAVES_BY_SPACES
	do
		freeSpaceMB=`ssh $machine sudo df $DF_BLOCKSIZE_SCALE | grep -m 1 "\% \/" | awk 'BEGIN{}{print $4}'`
		if (($freeSpaceMB < $MACHINE_OS_FREE_MIN_SPACE));then
			echo "$echoPrefix: there is no enouth place on the OS-disk at $machine" | tee $ERROR_LOG
			errorFlag=1
		fi
	done
	
	checkFinish $errorFlag	
}

checkNfsLoggerSpace()
{
	local errorFlag=0
	
	echo "$echoPrefix:  ~~~ Checking minial disk space on NFS log dir ~~~"

	echo "$echoPrefix:  checking $NFS_RESULTS_DIR"
	currentDiskSpace=`df $DF_BLOCKSIZE_SCALE $NFS_RESULTS_DIR | grep / | awk '{print $3}'`
	if (( $currentDiskSpace < $NFS_LOG_DIR_MIN_SPACE )); then
		echo "$echoPrefix: ${bold}ERROR:${normal} Not enough space on $NFS_RESULTS_DIR. Need $NFS_LOG_DIR_MIN_SPACE got $currentDiskSpace"
		errorFlag=1
	fi
	
	checkFinish $errorFlag	
}

checkLocalLoggerSpace()
{
	local errorFlag=0
	
	echo "$echoPrefix: ~~~ Checking minial disk space on local log dir ~~~"

	echo "$echoPrefix:  checking $RES_SERVER:$LOCAL_RESULTS_DIR"
	currentDiskSpace=`ssh $RES_SERVER df $DF_BLOCKSIZE_SCALE $LOCAL_RESULTS_DIR | grep / | awk '{print $3}'`
	if (( $currentDiskSpace < $LOCAL_LOG_DIR_MIN_SPACE )); then
		echo "$echoPrefix: ${bold}ERROR:${normal} Not enough space on $RES_SERVER:$LOCAL_RESULTS_DIR. Need $LOCAL_LOG_DIR_MIN_SPACE got $currentDiskSpace"
		errorFlag=1
	fi
	#exit $EEC3
	checkFinish $errorFlag	
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
	dirExists=`ssh $machine ls -ld $i | grep -c $i`
	if (($dirExists!=1)); then
		echo "$echoPrefix: ${bold}ERROR:${normal} No such folder $i on $machine - Exiting"
		errorFlag=1
	else
		currentDirPermissions=`ssh $machine ls -ld $i | cut --delimiter=" " -f 1`
		currentDirOwner=`ssh $machine ls -ld $i | cut --delimiter=" " -f 3`
		if [ $currentDirOwner != $USER ]; then
			echo "$echoPrefix: ${bold}ERROR:${normal} Owner of $i on $machine should be set to $USER but instead it is set to $currentDirOwner"
			errorFlag=1
		fi
		userPermissions=`echo "$currentDirPermissions" | cut -c 2-4`
		if [ $userPermissions != $USER_PERMISSIONS ] ; then
			echo "$echoPrefix: ${bold}ERROR:${normal} $USER on $machine needs rwx permissions for $i but got only $userPermissions"
			errorFlag=1
		fi
		#othersPermissions=`echo "$currentDirPermissions" | cut -c 8-10`
		#if [ $othersPermissions != $OTHERS_PERMISSIONS ] ; then
		#	echo "$echoPrefix: ${bold}ERROR:${normal} $USER on $machine is not dir owner of $i  so OTHER dir permissions should be set to rwx but is only set to $othersPermissions"
		#	errorFlag=1
		#fi
	fi
	retVal_checkPermissionsOnMachine=$errorFlag;
}

checkPermissions()
{
	local errorFlag=0

	echo "$echoPrefix: ~~~ Checking permissions on hadoop & hdfs directories ~~~"
	
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

checkHdfsSpaceOnMachineDir()
{
	local machine=$1
	local dirs=$2
	local threshold=$3
	local errorFlag=0
	
	for i in $dirs;do
		echo "$echoPrefix: checking directory $i on $machine"
		currentDiskSpace=`ssh $machine df $DF_BLOCKSIZE_SCALE $i | grep / | awk '{print $4}'`
		if (( $currentDiskSpace < $threshold )); then
			errorFlag=1
			echo "$echoPrefix: ${bold}ERROR:${normal} Not enough space on $machine on dir $i. Need $threshold got $currentDiskSpace"
		fi
	done
		
	retVal_checkHdfsSpaceOnMachineDir=$errorFlag
}

checkHdfsSpace()
{
	local errorFlag=0

	echo "$echoPrefix: ~~~ Checking minimal disk space on hdfs directories ~~~"
	
	checkHdfsSpaceOnMachineDir "$MASTER" "$HADOOP_TMP_DIR_BY_SPACES" "$HADOOP_TMP_DIR_MIN_SPACE"
	errorFlag=$((errorFlag+retVal_checkHdfsSpaceOnMachineDir));
	
	checkHdfsSpaceOnMachineDir "$MASTER" "$DFS_NAME_DIR_BY_SPACES" "$DFS_NAME_DIR_MIN_SPACE"
	errorFlag=$((errorFlag+retVal_checkHdfsSpaceOnMachineDir));
	
	for s in $SLAVES_BY_SPACES
	do
		checkHdfsSpaceOnMachineDir "$s" "$MAPRED_LOCAL_DIR_BY_SPACES" "$MAPRED_LOCAL_DIR_MIN_SPACE"
		errorFlag=$((errorFlag+retVal_checkHdfsSpaceOnMachineDir));
		
		checkHdfsSpaceOnMachineDir "$s" "$DFS_DATA_DIR_BY_SPACES" "$DFS_DATA_DIR_MIN_SPACE"
		errorFlag=$((errorFlag+retVal_checkHdfsSpaceOnMachineDir));
	done
	
	checkFinish $errorFlag	
}

checkRamUsage()
{
	local errorFlag=0
	
	for s in $SLAVES_BY_SPACES
	do
		echo "$echoPrefix: ~~~ Checking free RAM on $s"
		availableRam=`ssh $s cat /proc/meminfo | grep MemFree | awk '{print $2}'` # Get available ram in KB
		if (( $availableRam<$MIN_RAM_REQUIRED )); then
			echo "$echoPrefix: ${bold}ERROR:${normal} Not enough free RAM on $s -  Need at least $MIN_RAM_REQUIRED KB but got only $availableRam KB"
			errorFlag=1
		else
			echo "$echoPrefix:RAM check OK on $s"
		fi
	done
	
	#checkFinish $errorFlag
}

checkCpuUsage()
{
	echo "$echoPrefix: ~~~ Checking CPU Usage (average of 5 samples)"
	for s in $SLAVES_BY_SPACES
	do
		CPU="0"
		for i in {1..$CPU_USAGE_SAMPLES_TO_AVERAGE_COUNT};
		do
			CPUTMP=`ssh $s /usr/bin/top -b -n1 | grep "Cpu(s)" | awk '{ split($5,a,"%") ; print (100-a[1])/100'}`
			CPU=$(awk -v n1="$CPU" -v n2="$CPUTMP" 'BEGIN{print n1+n2}')
		done
		CPU=$(awk -v n1="$CPU" 'BEGIN{print n1/5}')
	#	CPU=`ssh $s /usr/bin/top -b -n1 | grep "Cpu(s)" | awk '{ split($5,a,"%") ; print (100-a[1])/100'}`
		CPU_CMP=$(awk -v n1="$CPU" -v n2="$MAX_CPU_USAGE" 'BEGIN{print (n1>n2)?1:0 }')
		echo "$echoPrefix: CPU usage on $s is $CPU"
		if [ "$CPU_CMP" -eq 1 ] ; then
			echo "$echoPrefix: ${bold}WARNING:${normal} CPU on $s Exceeds $MAX_CPU_USAGE"
		fi
	done
	#exit $EEC3
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

## Minimum disk space values (Get in MB from user, NEED TO CONVERT TO BYTES)
if [ -z $MAPRED_LOCAL_DIR_MIN_SPACE ]; then
	MAPRED_LOCAL_DIR_MIN_SPACE=$DEFAULT_MAPRED_LOCAL_DIR_MIN_SPACE # 2GB default value
fi

if [ -z $HADOOP_TMP_DIR_MIN_SPACE ]; then
	HADOOP_TMP_DIR_MIN_SPACE=$DEFAULT_HADOOP_TMP_DIR_MIN_SPACE # 2GB default value
fi

if [ -z $DFS_NAME_DIR_MIN_SPACE ]; then
	DFS_NAME_DIR_MIN_SPACE=$DEFAULT_DFS_NAME_DIR_MIN_SPACE # 2GB default value
fi

if [ -z $DFS_DATA_DIR_MIN_SPACE ]; then
	DFS_DATA_DIR_MIN_SPACE=$DEFAULT_DFS_DATA_DIR_MIN_SPACE # 2GB default value
fi


if [ -z $MACHINE_OS_FREE_MIN_SPACE ]; then
	MACHINE_OS_FREE_MIN_SPACE=$DEFAULT_MACHINE_OS_FREE_MIN_SPACE # 1GB default value
fi

## Max CPU Usage = (0<p<1)
if [ -z $MAX_CPU_USAGE ]; then
	MAX_CPU_USAGE=$DEFAULT_MAX_CPU_USAGE # 20% default value
fi

## Minimum RAM value (Get in MB from user, NEED TO CONVERT TO KILOBYTES)
if [ -z $MIN_RAM_REQUIRED ]; then
	MIN_RAM_REQUIRED=$DEFAULT_MIN_RAM_REQUIRED # 32GB default value
fi
## Conversion from MB to KB
MIN_RAM_REQUIRED=$(($MIN_RAM_REQUIRED*1024))

while getopts ":rlncwoiph" Option
do
	case ${Option} in
    		"r"     ) checkRamUsage ;; #ramFlag=1 ;;
			"l"     ) checkLocalLoggerSpace ;; #localLoggersSpaceFlag=1 ;; 
			"n"     ) checkNfsLoggerSpace ;; #nfsLoggersSpaceFlag=1 ;;
	    	"c"     ) checkCpuUsage ;; #cpuFlag=1 ;; 
			"w"		) checkSwapoff ;;# swapoffFlag=1 ;; 
			"o"		) checkOsFreeSpace ;; #osFreeSpaceFlag=1 ;;
			"i"		) checkOsFreeSpaceInit ;; # osFreeSpaceMasterInitFlag=1 ;;
			"p"     ) checkPermissions ;;#permissionsFlag=1 ;; 
			"h"		) checkHdfsSpace ;; #hdfsSpaceFlag=1 ;;
		*     	) echo "$echoPrefix: wrong input" ;  exit $SEC ;;   # Default.
	esac
done
