#!/bin/bash

echoPrefix=$(basename $0)
headline=""
urlLine=""
kernelCorePattern="$KERNEL_CORE_PATTERN_PROPERTY = $CORES_DIR/$CORES_PATTERN"

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
	git clone $GIT_HADOOPS_DIR $gitHadoopTempDir
	cd $gitHadoopTempDir/
	currentVersion=`git branch -r | grep $GIT_HADOOP_VERSION`

	if ((`echo $currentVersion | grep -c ""` != 1));then
		echo "$echoPrefix: error during getting the right hadoop version. [found: $currentVersion] " | tee $ERROR_LOG
		exit $EEC1
	else
		echo "$echoPrefix: checking-out version $currentVersion"
		git checkout $currentVersion
		workingFolder=$hadoopHome/$GIT_HADOOP_VERSION
		mkdir $workingFolder
		mv $gitHadoopTempDir/* $workingFolder # move regular files
		mv $gitHadoopTempDir/.* $workingFolder # move hidden files
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
		#command="sed '/kernel.core_pattern/ c $kernelCorePattern' $SYSCTL_PATH > $tempSysctl"
		#echo COMMAND: $command
		#eval ssh $node 'echo '/kernel.core_pattern/ c $kernelCorePattern'\\\"' ${SYSCTL_PATH}' #> $tempSysctl; echo -f $tempSysctl $SYSCTL_PATH"
		#eval ssh $node ""
		#mv -f $tempSysctl $SYSCTL_PATH
	elif (($kernelLineStatus == 0));then # adding a new line
		sudo ssh $node "sed '/# Useful for debugging multi-threaded applications/ a $kernelCorePattern' $SYSCTL_PATH > $tempSysctl; mv -f $tempSysctl $SYSCTL_PATH"
	else
		echo "$echoPrefix: problematic $SYSCTL_PATH file - contains more duplicate kernel.core_pattern property" | tee $ERROR_LOG
		exit $EEC1
	fi
}

# preparing the master
mkdir $STATUS_DIR
hadoopHome=$TMP_DIR
echo "$echoPrefix: mkdir $hadoopHome"
mkdir -p $hadoopHome
sudo chown -R $USER $hadoopHome


# in case we're running something from trunk
if (( $CO_FLAG == 1 ))
then
	coHadoopFromGit

	cd $workingFolder											
	echo "$echoPrefix: /usr/local/ant-1.8.2/bin/ant -Djava5.home=$JAVA_HOME clean package"  #building
	/usr/local/ant-1.8.2/bin/ant -Djava5.home=$JAVA_HOME clean package > $STATUS_DIR/buildHadoop.txt	
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
	
	echo "workingFolder=$MY_HADOOP_HOME"
	workingFolder=$MY_HADOOP_HOME
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
	sed "/export JAVA_HOME=/ c $javaHomeLine" $myHadoopHome/$HADOOP_CONF_RELATIVE_PATH/hadoop-env.sh > $myHadoopHome/$HADOOP_CONF_RELATIVE_PATH/hadoop-env2.sh
	sed "/export HADOOP_CLASSPATH=/ c export HADOOP_CLASSPATH=${HADOOP_CLASSPATH}${RPM_JAR}" $myHadoopHome/$HADOOP_CONF_RELATIVE_PATH/hadoop-env2.sh > $myHadoopHome/$HADOOP_CONF_RELATIVE_PATH/hadoop-env.sh
	#rm -f $myHadoopHome/$HADOOP_CONF_RELATIVE_PATH/hadoop-env2.sh
if [[ `cat $myHadoopHome/$HADOOP_CONF_RELATIVE_PATH/hadoop-env.sh` == *COVF* ]]; then
	echo "Changing COVFILE in hadoop-env export COVFILE=${COVFILE}"
	sed "/export COVFILE=/ c export COVFILE=${COVFILE}" $myHadoopHome/$HADOOP_CONF_RELATIVE_PATH/hadoop-env2.sh > $myHadoopHome/$HADOOP_CONF_RELATIVE_PATH/hadoop-env.sh
else
	echo "there's no COVFILE exported in hadoop-evn.sh";
	echo "export COVFILE=$COVFILE" >> $myHadoopHome/$HADOOP_CONF_RELATIVE_PATH/hadoop-env.sh
fi

#echo "export COVFILE=/$COVFILE" >> $DEFAULT_MY_HADOOP_HOME/$HADOOP_CONF_RELATIVE_PATH/hadoop-env.sh
rm -f $myHadoopHome/$HADOOP_CONF_RELATIVE_PATH/hadoop-env2.sh

echo -e \\n
echo "$echoPrefix: MY_HADOOP_HOME is $myHadoopHome"
sudo chown -R $USER $myHadoopHome
confDir=$myHadoopHome/$HADOOP_CONF_RELATIVE_PATH
scp $TESTS_PATH/slaves $confDir # copy the general slaves file, whick contains all of the slaves in the configuration-csv file, for setting-up the cluster 
echo -e \\n

if (($RPM_FLAG==1));then
	if rpm -qa | grep -q libuda; then
		echo "$echoPrefix: uninstalling the existing RPM"
		sudo rpm -e libuda;
	fi

	if (($CODE_COVE_FLAG==1)); then
		echo "CODE COVERAGE FLAG is turned on!!!!"
		echo "turning Bullseye ON!!!!!!!!!!!!!!!!"
		
		#bash $SCRIPTS_DIR/bullseyeRunner.sh // in this part insert bullseye install
		cov01 -1
	else 
		cov01 -0
	fi
	
	
	echo "cov01 -s # bullseye Flag stat"
	cov01 -s  # 
	bash $TMP_DIR/$TRUNK_RPM_BUILD_RELATIVE_PATH > $STATUS_DIR/buildHadoop.txt #building rpm
	
	buildRpmGit
	
	
	if (($CODE_COVE_FLAG==1)); then
		echo "cov01 -0 # bullseye Flag stat"
		cov01 -0  # 
		echo "cov01 -s # shutting down bullseye Flag"
		cov01 -s # shutting down bullseye Flag
		for slave in `cat $myHadoopHome/$HADOOP_CONF_RELATIVE_PATH/slaves`
			do
				echo "$COVFILE $slave:/tmp/"
				scp $COVFILE $slave:/tmp/
			done 
	fi
	
	echo "WAWAWAWWWWWWWWWAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

	
	#$myHadoopHome/bin/slaves.sh sudo rpm -e libuda;
	cd ~
	cd $RPMBUILD_DIR
	currentRpm=`pwd`/`ls -t | grep -m 1 ""`
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

echo "$echoPrefix: setting $kernelCorePattern on $SYSCTL_PATH"
setCoreDir `hostname`

echo "$echoPrefix: $killing all java processes"
sudo pkill -9 java

# preparing the slaves
source $TESTS_PATH/general.sh
#maxSlaves=`cat $confDir/slaves | grep -c ""`
#if [[ -n $MAX_SLAVES ]];then
#	maxSlaves=$MAX_SLAVES
#fi

for slave in $RELEVANT_SLAVES_BY_SPACES
do
	echo -e \\n\\n
	echo "$echoPrefix: ${slave}:"
	echo "$echoPrefix: cleaning temp directory"
#bash $SCRIPTS_DIR/safeRemove.sh $echoPrefix "ssh $slave rm -rf $TMP_DIR/\*" $TMP_DIR
	ssh $slave rm -rf $TMP_DIR/\*
	echo "$echoPrefix: killing all java processes"
	sudo ssh $slave pkill -9 java
	
	echo "$echoPrefix: copying hadoop"
	ssh $slave mkdir -p $myHadoopHome
	scp -r $myHadoopHome/* $slave:$myHadoopHome > /dev/null # the redirection is just to ignore the scp long output
	
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
	
	echo "$echoPrefix: setting $kernelCorePattern on $SYSCTL_PATH"
	setCoreDir $slave
done
echo -e \\n\\n

sourceRpmDir=$TMP_DIR/$CURRENT_DATE
destRpmDir=$RELEASE_DIR/$RELEASE_RPM_RELATIVE_DIR
echo "$echoPrefix: copying the rpm to $destRpmDir"
mkdir $sourceRpmDir
cp $currentRpm $sourceRpmDir
mv -r $sourceRpmDir $destRpmDir

echo "$echoPrefix: finishing setting-up the cluster, under $myHadoopHome"

echo "
	#!/bin/sh
	export MY_HADOOP_HOME='$myHadoopHome'
	export HEADLINE='$headline'
	export RPM_LINE='$rpmLine'
	#export CURRENT_DATE='$CURRENT_DATE'
	export UDA_CORES_DIR='$udaCores'
" > $TMP_DIR/setupExports.sh
