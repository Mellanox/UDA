#!/bin/bash

echoPrefix=$(basename $0)
headline=""
urlLine=""
sysctl="/etc/sysctl.conf"
#sysctl="/labhome/oriz/sysctl.conf"
kernelCorePattern="kernel.core_pattern = $CORES_DIR/$CORES_PATTERN"
#CURRENT_DATE=`date +"%Y_%m_%d___%H_%M"`

setCoreDir ()
{
	node=$1
	# managing the core files location
	kernelLineStatus=`ssh $node "grep -c kernel.core_pattern $sysctl"`
	tempSysctl=$TMP_DIR/`basename $sysctl`
	if (($kernelLineStatus == 1));then # replacing the current line
		sudo ssh $node "sed '/kernel.core_pattern/ c $kernelCorePattern' $sysctl > $tempSysctl; mv -f $tempSysctl $sysctl"
		#command="sed '/kernel.core_pattern/ c $kernelCorePattern' $sysctl > $tempSysctl"
		#echo COMMAND: $command
		#eval ssh $node 'echo '/kernel.core_pattern/ c $kernelCorePattern'\\\"' ${sysctl}' #> $tempSysctl; echo -f $tempSysctl $sysctl"
		#eval ssh $node ""
		#mv -f $tempSysctl $sysctl
	elif (($kernelLineStatus == 0));then # adding a new line
		sudo ssh $node "sed '/# Useful for debugging multi-threaded applications/ a $kernelCorePattern' $sysctl > $tempSysctl; mv -f $tempSysctl $sysctl"
	else
		echo "$echoPrefix: problematic $sysctl file - contains more duplicate kernel.core_pattern property" | tee $ERROR_LOG
		exit $EEC1
	fi
}

# preparing the master
hadoopHome=$TMP_DIR/hadoop_$CURRENT_DATE
echo "$echoPrefix: mkdir $hadoopHome"
mkdir -p $hadoopHome
sudo chown -R $USER $hadoopHome
cd $hadoopHome

# in case we're running something from trunk
if (( $CO_FLAG == 1 ))
then 
		# getting the hadoop from the svn
	if [ -z "$SVN_REVISION" ]; then
		echo "$echoPrefix: svn co $SVN_HADOOP"
		svn co $SVN_HADOOP > $TMP_DIR/coHadoop.txt
	else 
		echo  "$echoPrefix: svn co -r $SVN_REVISION $SVN_HADOOP"
		svn co -r $SVN_REVISION $SVN_HADOOP $TMP_DIR/coHadoop.txt
	fi

		# building the hadoop
	hadoopFolder=`ls -t $hadoopHome | grep -m 1 ""`
	workingFolder=$hadoopHome/$hadoopFolder
	mkdir -p $workingFolder
	echo WORKING DIR: $workingFolder
	cd $workingFolder
	echo "$echoPrefix: /usr/local/ant-1.8.2/bin/ant -Djava5.home=/usr/lib64/java/jdk1.6.0_25 clean package"  #building
	/usr/local/ant-1.8.2/bin/ant -Djava5.home=$JAVA_HOME clean package | tee build.txt	
	buildStatus=`cat build.txt | grep -c "BUILD SUCCESSFUL"`

	if (($buildStatus == 0));then 
		echo "$echoPrefix: BUILD FAILED!" | tee $ERROR_LOG
		exit $EEC1
	fi
	
	if [[ $hadoopFolder == "hadoop-1.1.0-patched-v2" ]];then
		echo "$echoPrefix: hadoop version is hadoop-1.1.0-patched-v2"  #building
			# coping the SNAPSHOT folder to the hadoop-home directory
		snapshotFolder=`find $workingFolder/build -maxdepth 1 -mindepth 1 -type d | grep "SNAPSHOT"`
		matchCount=`echo $snapshotFolder | grep -c "SNAPSHOT"`
		if (($matchCount != 1));then
			echo "error: found $matchCount SNAPSHOT folders" | tee $ERROR_LOG
			exit $EEC1
		fi
		cp $snapshotFolder/* $workingFolder/
	fi
	javaHomeLine="export JAVA_HOME=$JAVA_HOME"
	sed "/export JAVA_HOME=/ c $javaHomeLine" $workingFolder/conf/hadoop-env.sh > $workingFolder/conf/hadoop-env2.sh
	sed "/export HADOOP_CLASSPATH=/ c export HADOOP_CLASSPATH=${HADOOP_CLASSPATH}${RPM_JAR}" $workingFolder/conf/hadoop-env2.sh > $workingFolder/conf/hadoop-env.sh
	rm -f $workingFolder/conf/hadoop-env2.sh
	revision=`svn info | grep "Revision:" | awk '{print $2}'`
	#lastChangedRev=`svn info | grep "Last Changed Rev:" | awk '{print $4}'`
	#echo "$echoPrefix: Last changed revision is $lastChangedRev"
	
	headline="Daily Smoke Test of revision $revision"
	urlLine="from $SVN_HADOOP";
else  # in case we're running a totaly-build and ready hadoop from NFS
	workingFolder=$HADOOP_DIR
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

echo -e \\n\\n
echo "$echoPrefix: MY_HADOOP_HOME is $myHadoopHome"
sudo chown -R $USER $myHadoopHome
confDir=$myHadoopHome/conf
scp $TESTS_PATH/slaves $confDir # copy the general slaves file, whick contains all of the slaves in the configuration-csv file, for setting-up the cluster 
hadoopVersion=`echo $(basename $myHadoopHome) | sed s/[.]/_/g`
echo "$echoPrefix: VERSION:" $hadoopVersion
echo -e \\n\\n

if (($RPM_FLAG==1));then
	if rpm -qa | grep -q libuda; then
		echo "$echoPrefix: uninstalling the existing RPM"
		sudo rpm -e libuda;
	fi

	#sudo rpm -e libuda #sudo rpm -ivh $RPM;sudo rpm -iq libuda
	cd ~
	rpmDir="rpmbuild/SOURCES"
	mkdir -p $rpmDir
	cd $TMP_DIR
	echo "$echoPrefix: svn co $SVN_TRUNK"
	svn co $SVN_TRUNK > $TMP_DIR/coTrunk.txt
	bash $TMP_DIR/trunk/$SVN_RPM_BUILD   #building rpm
	
	#$myHadoopHome/bin/slaves.sh sudo rpm -e libuda;
	cd ~
	cd rpmbuild/RPMS/x86_64
	currentRpm=`ls -t | grep -m 1 ""`
	currentRpm=`pwd`/`ls -t | grep -m 1 ""`
	rpmLine="RPM: $currentRpm"
	echo "$echoPrefix: installing RPM: $currentRpm"
	sudo rpm -ivh $currentRpm
	installedRpm=`sudo rpm -iq libuda`
	echo "$echoPrefix: the installed RPM is $installedRpm"
	#if [[ $currentRpm != "${installedRpm}.rpm" ]];then
	if ! echo $currentRpm | grep $installedRpm ;then
		echo "$echoPrefix: error occured when installing RPM on `hostname`" | tee $ERROR_LOG
		exit $EEC1
	fi
fi	

echo "$echoPrefix: setting $kernelCorePattern"
setCoreDir `hostname`

echo "$echoPrefix: $killing all java processes"
sudo pkill -9 java
 
# prepering dir on the collecting-server to the tests-logs 
sudo mkdir -p $LOCAL_RESULTS_DIR 
sudo chown -R $USER $LOCAL_RESULTS_DIR
currentResultsDir=$LOCAL_RESULTS_DIR/logs_${CURRENT_DATE}
ssh $RES_SERVER sudo mkdir -p $currentResultsDir
ssh $RES_SERVER sudo chown -R $USER $currentResultsDir

# preparing the slaves
maxSlaves=`cat $confDir/slaves | grep -c ""`
if [[ -n $MAX_SLAVES ]];then
	maxSlaves=$MAX_SLAVES
fi

i=1
for slave in `cat $confDir/slaves`
do
	echo "$echoPrefix: ${slave}:"
	echo "$echoPrefix: cleaning temp directory"
#bash $SCRIPTS_DIR/safeRemove.sh $echoPrefix "ssh $slave rm -rf $TMP_DIR/\*" $TMP_DIR
	ssh $slave rm -rf $TMP_DIR/\*
	echo "$echoPrefix: killing all java processes"
	sudo ssh $slave pkill -9 java
	
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
	
	echo "$echoPrefix: setting $kernelCorePattern"
	setCoreDir $slave
	echo -e \\n\\n
	
	if (($i >= $maxSlaves));then
		break
	fi
	i=$((i+1))
done

echo "$echoPrefix: finishing setting-up the cluster"

#udaCores=$UDA_CORES_DIR
#if [[ $udaCores == "MY_HADOOP_HOME" ]];then
#	eval udaCores=$myHadoopHome
#fi
#echo udaCores is: $udaCores

echo "
	#!/bin/sh
	export MY_HADOOP_HOME='$myHadoopHome'
	export HADOOP_CONF_DIR='$confDir'
	export HADOOP_VERSION='$hadoopVersion'
	export HEADLINE='$headline'
	export RPM_LINE='$rpmLine'
	#export CURRENT_DATE='$CURRENT_DATE'
	export CURRENT_LOCAL_RESULTS_DIR='$currentResultsDir'
	export UDA_CORES_DIR='$udaCores'
" > $TMP_DIR/setupExports.sh
