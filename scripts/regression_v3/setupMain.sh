#!/bin/bash

coHadoopFromSvn()
{
	cd $hadoopHome
		# getting the hadoop from the svn
	if [ -z "$SVN_REVISION" ]; then
		echo "$echoPrefix: svn co $SVN_HADOOP"
		svn co $SVN_HADOOP > $STATUS_DIR/coHadoop.txt
	else 
		echo  "$echoPrefix: svn co -r $SVN_REVISION $SVN_HADOOP"
		svn co -r $SVN_REVISION $SVN_HADOOP > $STATUS_DIR/coHadoop.txt
	fi
	
			# building the hadoop
	hadoopFolder=`ls -t $hadoopHome | grep -m 1 "hadoop"`
	workingFolder=$hadoopHome/$hadoopFolder
	mkdir -p $workingFolder
	revision=`svn info | grep "Revision:" $workingFolder | awk '{print $2}'`
}

buildRpmSvn()
{
	echo "$echoPrefix: svn co $SVN_TRUNK"
	svn co $SVN_TRUNK > $TMP_DIR/coTrunk.txt
	echo "$echoPrefix: building the rpm"
	bash $TMP_DIR/$TRUNK_RPM_BUILD_RELATIVE_PATH > $STATUS_DIR/buildHadoop.txt #building rpm
}

coHadoopFromGit()
{
	gitHadoopTempDir=$TMP_DIR/$GIT_CO_HADOOP_DIR_NAME
	mkdir $gitHadoopTempDir
	echo "$echoPrefix: git clone $GIT_HADOOPS_DIR $gitHadoopTempDir"
	git clone $GIT_HADOOPS_DIR $gitHadoopTempDir
	cd $gitHadoopTempDir/
	currentVersion=`git branch -r | grep $GIT_HADOOP_VERSION`

	if ((`echo $currentVersion | grep -c ""` != 1));then
		echo "$echoPrefix: error during getting the right hadoop version. [found: $currentVersion] " | tee $ERROR_LOG
		exit $EEC1
	else
		echo "$echoPrefix: checking-out version $currentVersion"
		currentVersion=${currentVersion:9}
		echo "$echoPrefix: current version is $currentVersion"
		git checkout $currentVersion
		workingFolder=$hadoopHome/$GIT_HADOOP_VERSION
		mkdir $workingFolder
		mv $gitHadoopTempDir/* $workingFolder # move regular files
		mv $gitHadoopTempDir/.* $workingFolder # move hidden files
		echo "$echoPrefix: rm -rf $gitHadoopTempDir"
		sudo rm -rf $gitHadoopTempDir
		
	fi
}

buildRpmGit()
{
	echo "$echoPrefix: getting the master directory from Git"
	gitMasterTempDir=$TMP_DIR/$GIT_CO_MASTER_DIR_NAME
	mkdir $gitMasterTempDir
	git clone $GIT_MASTER_DIR $gitMasterTempDir
	rpmBuild=$gitMasterTempDir/$TRUNK_RPM_BUILD_RELATIVE_PATH
	echo "$echoPrefix: building the rpm from $rpmBuild"
	bash $rpmBuild > $STATUS_DIR/buildHadoop.txt #building rpm
	if ((`cat $STATUS_DIR/buildHadoop.txt | grep -c "SUCCESS: Your RPM is under"` != 1));then
		echo "$echoPrefix: failed to build the rpm" | tee $ERROR_LOG
		exit $EEC1
	fi
}

setCoreDir ()
{
	node=$1
	# managing the core files location
	kernelLineStatus=`ssh $node "grep -c $KERNEL_CORE_PATTERN_PROPERTY $SYSCTL_PATH"`
	tempSysctl=$TMP_DIR/`basename $SYSCTL_PATH`
	if (($kernelLineStatus == 1));then # replacing the current line
		sudo ssh $node "sed '/kernel.core_pattern/ c $kernelCorePattern' $SYSCTL_PATH > $tempSysctl; mv -f $tempSysctl $SYSCTL_PATH"
	elif (($kernelLineStatus == 0));then # adding a new line
		sudo ssh $node "sed '/# Useful for debugging multi-threaded applications/ a $kernelCorePattern' $SYSCTL_PATH > $tempSysctl; mv -f $tempSysctl $SYSCTL_PATH"
	else
		echo "$echoPrefix: problematic $SYSCTL_PATH file - contains more duplicate kernel.core_pattern property" | tee $ERROR_LOG
		exit $EEC1
	fi
}

setHugePages ()
{
	node=$1
	showHugePagesCmd="grep HugePages_Total /proc/meminfo"
	showShmMaxCmd="cat /proc/sys/kernel/shmmax"
	lastHugePagesCount=`ssh $node $showHugePagesCmd | awk '{print $2}'`
	lastShmMax=`ssh $node $showShmMaxCmd`
	
	if (($HUGE_PAGES_COUNT == 0));then
		shmMaxNeeded=$SYSTEM_DEFAULT_SHM_MAX_SIZE
	else
		hugePageSizeKb=`ssh $node grep Hugepagesize /proc/meminfo | awk '{print $2}'`
		shmMaxNeeded=$((HUGE_PAGES_COUNT*hugePageSizeKb*1024))
	fi
	sudo ssh $node "echo $shmMaxNeeded > /proc/sys/kernel/shmmax; echo $HUGE_PAGES_COUNT > /proc/sys/vm/nr_hugepages"
	newHugePageCount=`ssh $node $showHugePagesCmd | awk '{print $2}'`
	newShmMax=`ssh $node $showShmMaxCmd`
	echo "$echoPrefix: huge pages are $newHugePageCount, shmmax is $newShmMax"
	
	echo "sudo echo $lastHugePagesCount > /proc/sys/vm/nr_hugepages;
		echo $lastShmMax > /proc/sys/kernel/shmmax;
		echo `eval $showHugePagesCmd`, shmmax is `eval $showShmMaxCmd`" >> $slavesExitScript
		
	restartClusterConfiguration=1
}

setRdmaMtt ()
{
	node=$1
	showNumMttCmd="cat /sys/module/mlx4_core/parameters/log_num_mtt"
	showMttsPerSegCmd="cat /sys/module/mlx4_core/parameters/log_mtts_per_seg"
	if (($logNumMtt == `eval ssh $node $showNumMttCmd`)) && (($logMttsPerSeg == `eval ssh $node $showMttsPerSegCmd`));then
		echo "$echoPrefix: no need to configure log_num_mtt and log_mtts_per_seg"
		return 0;
	fi

	echo "$echoPrefix: setting log_num_mtt and log_mtts_per_seg:"
	matchesCount=`ssh $node ls $MLNX_CONF_PATH | grep -c ""`
	if (($matchesCount != 1));then
			echo "$echoPrefix: found $matchesCount matches to {MELLANOX}.conf file. please check" | tee $ERROR_LOG
			exit $EEC1
	fi	
	optionsLine=`ssh $node "grep '$MLNX_CONF_OPTIONS_LINE' $MLNX_CONF_PATH"`
	if ((`echo $optionsLine | grep -c ""` != 1));then
			echo "$echoPrefix: found $optionsLine matches to options line. please check" | tee $ERROR_LOG
			exit $EEC1
	fi
	mlnxConfFileName=`basename $MLNX_CONF_PATH`
	mlnxConfTmpFile=$TMP_DIR/$mlnxConfFileName
	mlnxConfBackupFile=${mlnxConfTmpFile}${BACKUP_POSTFIX}
		# saving the {MELLANOX}.conf file in order to return to the first configuration when finishing (in exitMain.sh)
	if (($firstMttSetupFlag == 1));then
		sudo ssh $node cp $MLNX_CONF_PATH $mlnxConfTmpFile
		sudo ssh $node mv $mlnxConfTmpFile $mlnxConfBackupFile
		echo "sudo mv $mlnxConfBackupFile $mlnxConfTmpFile;
			sudo mv $mlnxConfTmpFile `dirname $MLNX_CONF_PATH`;
			echo log_num_mtt is `eval $showNumMttCmd`, log_mtts_per_seg is `eval $showMttsPerSegCmd`" >> $slavesExitScript
		firstMttSetupFlag=0
	fi
	
	sudo ssh $node sed "'/$MLNX_CONF_OPTIONS_LINE/ c $optionsLine log_num_mtt=$LOG_NUM_MTT log_mtts_per_seg=$LOG_MTTS_PER_SEG' $MLNX_CONF_PATH > $mlnxConfTmpFile"
	sudo ssh $node mv $mlnxConfTmpFile $MLNX_CONF_PATH
	sudo ssh $node $OPENIBD_PATH restart
	echo "$echoPrefix: log_num_mtt is `eval ssh $node $showNumMttCmd`, log_mtts_per_seg is `eval ssh $node $showMttsPerSegCmd`"

	restartClusterConfiguration=1
}

setupConfsDir=$1
echoPrefix=`eval $ECHO_PATTERN`

firstMttSetupFlag=$FIRST_MTT_SETUP_FLAG
headline=""
urlLine=""
kernelCorePattern="$KERNEL_CORE_PATTERN_PROPERTY = $CORES_DIR/$CORES_PATTERN"
restartClusterConfiguration=""

source $setupConfsDir/general.sh

slavesExitScript=$STATUS_DIR/slavesExitScript.sh
echo "" > $slavesExitScript
if [[ -f $slavesExitScript ]];then
	rm -f $slavesExitScript
fi
# preparing the master
hadoopHome=$TMP_DIR
#echo "$echoPrefix: mkdir $hadoopHome"
#mkdir -p $hadoopHome
#sudo chown -R $USER $hadoopHome
	# removing temp data between cluster-setup
rm -rf $TMP_DIR/${HADOOP_HOME_DIR_PREFIX}*
rm -rf $STATUS_DIR/*

logNumMtt=$LOG_NUM_MTT
if [ -z "$logNumMtt" ];then
    logNumMtt=$DEFAULT_LOG_NUM_MTT
fi

logMttsPerSeg=$LOG_MTTS_PER_SEG
if [ -z "$logMttsPerSeg" ];then
    logMttsPerSeg=$DEFAULT_LOG_MTTS_PER_SEG
fi

# in case we're running something from trunk
if (( $CO_FLAG == 1 ))
then
	coHadoopFromGit

	cd $workingFolder				
	
	buildOptions=""
	if (( $SNAPPY==1 ));then
		echo "$echoPrefix: using Sanppy"
		buildOptions="-Dcompile.native=true"
	fi						
	buildCmd="/usr/local/ant-1.8.2/bin/ant -Djava5.home=$JAVA_HOME $buildOptions clean package"
	echo "$echoPrefix: $buildCmd" 
	eval $buildCmd > $STATUS_DIR/buildHadoop.txt	
	buildStatus=`cat $STATUS_DIR/buildHadoop.txt | grep -c "BUILD SUCCESSFUL"`

	if (($buildStatus == 0));then 
		echo "$echoPrefix: BUILD FAILED!" | tee $ERROR_LOG
		exit $EEC1
	fi
	
	if [[ $GIT_HADOOP_VERSION == "hadoop-1.1.0-patched-v2" ]];then
		echo "$echoPrefix: hadoop version is hadoop-1.1.0-patched-v2"  #building
			# copying the SNAPSHOT folder to the hadoop-home directory
		snapshotFolder=`find $workingFolder/build -maxdepth 1 -mindepth 1 -type d | grep "SNAPSHOT"`
		matchCount=`echo $snapshotFolder | grep -c "SNAPSHOT"`
		if (($matchCount != 1));then
			echo "error: found $matchCount SNAPSHOT folders" | tee $ERROR_LOG
			exit $EEC1
		fi
		cp -r $snapshotFolder/* $workingFolder/
	fi
	
	headline="Daily Smoke Test of revision $revision"
	urlLine="from $SVN_HADOOP";
else  # in case we're running a totaly-build and ready hadoop from NFS

	if [ -z "$MY_HADOOP_HOME" ];then
		echo "$echoPrefix: MY_HADOOP_HOME must be set when working with local hadoop" | tee $ERROR_LOG
		exit $EEC1
	fi
	workingFolder=$MY_HADOOP_HOME_CLIENT
	lastChar=`echo $workingFolder | sed 's/^.*\(.\{1\}\)$/\1/'`
	if [[ $lastChar == "/" ]]; then
		workingFolder=${workingFolder%?}
	fi
	workingDir=`echo "$workingFolder" | awk ' BEGIN {FS="/"} {print $NF}'`

	echo "$echoPrefix: cp -r $workingFolder $hadoopHome/";
	cp -r $workingFolder $hadoopHome/; 
	echo "$echoPrefix: cp -r $workingFolder $hadoopHome/";
	cd $hadoopHome/$workingDir;
	workingFolder=$workingDir
	headline="Running hadoop from local directory"
fi

myHadoopHome=`pwd`
if [[ $myHadoopHome == "/" ]];then
	echo "$echoPrefix: MY_HADOOP_HOME is / !!" | tee $ERROR_LOG
	exit $EEC1
fi

javaHomeLine="export JAVA_HOME=$JAVA_HOME"
hadoopEnv=$myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env.sh
hadoopEnvTemp=$myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env2.sh
sed "/export JAVA_HOME=/ c $javaHomeLine" $hadoopEnv > $hadoopEnvTemp
sed "/export HADOOP_CLASSPATH=/ c export HADOOP_CLASSPATH=${HADOOP_CLASSPATH}${RPM_JAR}" $hadoopEnvTemp > $hadoopEnv
rm -f $hadoopEnvTemp

if (( $LZO==1 )); then
	echo "$echoPrefix: sed /export HADOOP_CLASSPATH=/ c export HADOOP_CLASSPATH=${HADOOP_CLASSPATH}:${RPM_JAR}${LZO_JAR} $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env2.sh > $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env.sh"
	sed "/export HADOOP_CLASSPATH=/ c export HADOOP_CLASSPATH=${HADOOP_CLASSPATH}${RPM_JAR}:${LZO_JAR}" $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env.sh > $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env2.sh
	
	echo "$echoPrefix: cat $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env2.sh"
	mv $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env2.sh  $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env.sh

	if [[ `cat $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env.sh` == *JAVA_LIBRARY_PATH* ]]; then
		echo "$echoPrefix: Changing JAVA_LIBRARY_PATH in hadoop-env"
		sed "/export JAVA_LIBRARY_PATH=/ c export JAVA_LIBRARY_PATH=/.autodirect/mtrswgwork/shania/hadoop/hortonworks-hadoop-lzo-cf4e7cb/build/native/Linux-amd64-64/.libs/" $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env.sh > $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env2.sh
		#mv $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env2.sh  $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env.sh
	
	else
		echo "$echoPrefix: there's no JAVA_LIBRARY_PATH exported in hadoop-env.sh "
		echo "export JAVA_LIBRARY_PATH=/.autodirect/mtrswgwork/shania/hadoop/hortonworks-hadoop-lzo-cf4e7cb/build/native/Linux-amd64-64/.libs/" >> $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env.sh
	fi
	
	echo "$echoPrefix: sed /JAVA_LIBRARY_PATH=''/ c #JAVA_LIBRARY_PATH=''  $myHadoopHome/bin/hadoop > $myHadoopHome/bin/hadoop2"
	sed "/JAVA_LIBRARY_PATH=''/ c #JAVA_LIBRARY_PATH='' " $myHadoopHome/bin/hadoop > $myHadoopHome/bin/hadoop2
	echo "$echoPrefix: mv $myHadoopHome/bin/hadoop2 $myHadoopHome/bin/hadoop"
	mv $myHadoopHome/bin/hadoop2 $myHadoopHome/bin/hadoop
	chmod 777  $myHadoopHome/bin/hadoop
	
#else
	#sed "/export HADOOP_CLASSPATH=/ c export HADOOP_CLASSPATH=${HADOOP_CLASSPATH}${RPM_JAR}" $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env.sh > $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env2.sh
	#mv $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env2.sh  $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env.sh
	#rm -f $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env2.sh
fi

if (( $SNAPPY==1 ))
then
	rpm -qa | grep snappy; 
	ans=$?; 
	if (( ans == 0 )); 
	then 
		echo "Snappy is allready here...";
	else 
		echo "sudo yum -y install snappy snappy-devel snappy.i386 snappy-devel.i386"
		sudo yum -y install snappy snappy-devel snappy.i386 snappy-devel.i386
	fi
	echo "scp /usr/lib64/libsnappy.so* $workingFolder/build/native/*/lib/"
	scp /usr/lib64/libsnappy.so* $workingFolder/build/native/*/lib/
	
	echo "RELEVANT_SLAVES_BY_SPACES $RELEVANT_SLAVES_BY_SPACES"
	for slave in $RELEVANT_SLAVES_BY_SPACES
	do
		echo "sudo scp /usr/lib64/libsnappy.so* $slave:/usr/lib64/"
		sudo scp /usr/lib64/libsnappy.so* $slave:/usr/lib64/
	done
fi	
	
if [[ `cat $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env.sh` == *COVF* ]]; then
	echo "Changing COVFILE in hadoop-env export COVFILE=${COVFILE}"
	sed "/export COVFILE=/ c export COVFILE=${COVFILE}" $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env.sh > $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env2.sh
	mv $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env2.sh  $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env.sh
else
	echo "there's no COVFILE exported in hadoop-evn.sh";
	echo "export COVFILE=$COVFILE" >> $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env.sh
fi

#echo "export COVFILE=/$COVFILE" >> $DEFAULT_MY_HADOOP_HOME/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env.sh
rm -f $myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH/hadoop-env2.sh

echo -e \\n
echo "$echoPrefix: MY_HADOOP_HOME is $myHadoopHome"
sudo chown -R $USER $myHadoopHome
#confDir=$myHadoopHome/$HADOOP_CONFIGURATION_DIR_RELATIVE_PATH
#scp $TESTS_DIR/slaves $confDir # copy the general slaves file, whick contains all of the slaves in the configuration-csv file, for setting-up the cluster 
echo -e \\n

echo "$echoPrefix: creating the needed directories"
sudo mkdir -p $DIRS_TO_CREATE
sudo chown -R $USER $DIRS_TO_CREATE 
sudo chgrp -R $GROUP_NAME $DIRS_TO_CREATE 

if (($RPM_FLAG==1));then
	if rpm -qa | grep -q libuda; then
		echo "$echoPrefix: uninstalling the existing RPM"
		sudo rpm -e libuda;
	fi
	
	if (($CODE_COVE_FLAG==1)); then
		echo "CODE COVERAGE FLAG is turned on!!!!"
		echo "turning Bullseye ON!!!!!!!!!!!!!!!!"
		sudo rm -rf /tmp/*.cov
		echo "sudo rm -rf /tmp/*.cov"
		
		#bash $SCRIPTS_DIR/bullseyeRunner.sh // in this part insert bullseye install
		cov01 -1
	else 
		cov01 -0
	fi
	echo "cov01 -s # bullseye Flag stat"
	cov01 -s  # 

	if [[ -z $CURRENT_RPM_DIR ]];then
		echo "$echoPrefix: start installing the rpm from Git"
		buildRpmGit
		cd ~
		cd $RPMBUILD_DIR
		currentRpm=`pwd`/`ls -t | grep -m 1 ""`
	else
		echo "$echoPrefix: installing the rpm locally from $CURRENT_RPM_DIR"
		currentRpm=$CURRENT_RPM_DIR
	fi

	if (($CODE_COVE_FLAG==1)); then
		echo "cov01 -0 # bullseye Flag stat"
		cov01 -0  # 
		echo "cov01 -s # shutting down bullseye Flag"
		cov01 -s # shutting down bullseye Flag
	for slave in $RELEVANT_SLAVES_BY_SPACES
			do
				ssh $slave sudo rm -rf /tmp/*.cov
				echo "$COVFILE $slave:/tmp/"
				scp $COVFILE $slave:/tmp/
			done 
	fi

	rpmLine="RPM: $currentRpm"
	echo "$echoPrefix: installing the rpm $currentRpm"
	sudo rpm -ivh $currentRpm
	installedRpm=`sudo rpm -iq libuda`
	echo "$echoPrefix: the installed RPM is $installedRpm"
	#if [[ $currentRpm != "${installedRpm}.rpm" ]];then
	if ! echo $currentRpm | grep $installedRpm ;then
		echo "$echoPrefix: error occured when installing RPM on `hostname`" | tee $ERROR_LOG
		exit $EEC1
	fi
fi	

echo "$echoPrefix: $killing all java processes"
sudo pkill -9 java

echo "$echoPrefix: setting $kernelCorePattern on $SYSCTL_PATH"
setCoreDir `hostname`

#setRdmaMtt `hostname`

# preparing the slaves

for slave in $RELEVANT_SLAVES_BY_SPACES
do
	echo -e \\n\\n
	echo "$echoPrefix: $slave:"
	
	if [[ $slave == $csvMASTER ]];then
		echo "$echoPrefix: node $slave is both master and slave. it already set"
		continue
	fi
	
	echo "$echoPrefix: cleaning temp directory"
#bash $SCRIPTS_DIR/safeRemove.sh $echoPrefix "ssh $slave rm -rf $TMP_DIR/\*" $TMP_DIR
	sudo ssh $slave mkdir -p $TMP_DIR
	sudo ssh $slave rm -rf $TMP_DIR/\*
	sudo ssh $slave chown -R $USER $TMP_DIR
	ssh $slave mkdir -p $STATUS_DIR
	ssh $slave rm -rf $STATUS_DIR/\*
	
	echo "$echoPrefix: killing all java processes"
	sudo ssh $slave pkill -9 java
		
	echo "$echoPrefix: copying hadoop"
	ssh $slave mkdir -p $myHadoopHome
	sudo scp -r $myHadoopHome/* $slave:$myHadoopHome > /dev/null # the redirection is just to ignore the scp long output
	sudo ssh $slave sudo chown -R $USER $myHadoopHome
	if (($RPM_FLAG == 1));then
		if ssh $slave rpm -qa | grep -q libuda; then
			echo "$echoPrefix: uninstalling the existing RPM"
			sudo ssh $slave rpm -e libuda;
		fi
		#sudo ssh $slave rpm -e libuda;
		echo "$echoPrefix: installing RPM: $currentRpm"
		sudo ssh $slave rpm -ivh $currentRpm
		installedRpm=`sudo ssh $slave rpm -iq libuda`
		echo "$echoPrefix: the installed RPM is $installedRpm"
		#if [[ $currentRpm != "${installedRpm}.rpm" ]];then
		if ! echo $currentRpm | grep $installedRpm ;then
			echo "$echoPrefix: error occured when installing RPM on `ssh $slave hostname`" | tee $ERROR_LOG # for avoiding printing the slave name with the interface prefix
			exit $EEC1
		fi
	fi
	
	echo "$echoPrefix: creating the needed directories"
	sudo mkdir -p $DIRS_TO_CREATE
	sudo chown -R $USER $DIRS_TO_CREATE
	sudo chgrp -R $GROUP_NAME $DIRS_TO_CREATE
		
	echo "$echoPrefix: setting $kernelCorePattern on $SYSCTL_PATH"
	setCoreDir $slave
	
	if (($HUGE_PAGES_COUNT != $DEFAULT_HUGE_PAGES_COUNT));then
		echo "$echoPrefix: setting huge pages"
		setHugePages $slave
	fi
	#setRdmaMtt $slave

done
echo -e \\n\\n

#sourceRpmDir=$TMP_DIR/$CURRENT_DATE
#destRpmDir=$RELEASE_DIR/$RELEASE_RPM_RELATIVE_DIR
#echo "$echoPrefix: copying the rpm to $destRpmDir"
#mkdir $sourceRpmDir
#cp $currentRpm $sourceRpmDir
#mv -r $sourceRpmDir $destRpmDir

echo "$echoPrefix: finishing setting-up the cluster, under $myHadoopHome"

echo "
	#!/bin/sh
	export MY_HADOOP_HOME='$myHadoopHome'
	export HEADLINE='$headline'
	export RPM_LINE='$rpmLine'
	#export CURRENT_DATE='$CURRENT_DATE'
	export UDA_CORES_DIR='$udaCores'
	export EXIT_SCRIPTS_SLAVES='$slavesExitScript'
	export RESTART_CLUSTER_CONF_FLAG=$restartClusterConfiguration
	export FIRST_MTT_SETUP_FLAG=$firstMttSetupFlag
" > $TMP_DIR/setupExports.sh
