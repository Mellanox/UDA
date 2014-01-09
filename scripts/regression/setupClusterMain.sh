#!/bin/bash

getBranchFromGit() 
{
	local gitProject=$1
	local gitBranch=$2
	local localBranchDir=$3
	
	if [[ -z $gitBranch ]];then
		gitBranch=$UDA_DEFAULT_BRANCH
	fi
	
	echo "$echoPrefix: getting branch $gitBranch from git"
	local gitBranchLocalDir=$localBranchDir/$gitBranch
	mkdir $gitBranchLocalDir
	echo "$echoPrefix: git clone $gitProject $gitBranchLocalDir"
	git clone $gitProject $gitBranchLocalDir
	cd $gitBranchLocalDir/
	local currentVersionCount=`git branch -r | grep $gitBranch | grep -c ""`
	if [[ $gitBranch != master~* ]] && (($currentVersionCount == 0));then
		local currentVersion=`git branch -r | grep $gitBranch`
		echo "$echoPrefix: error during getting the right hadoop version. [found: $currentVersion] " | tee $ERROR_LOG
		exit $EEC1
	else
		git checkout $gitBranch

		getBranchFromGitRetVal=$gitBranchLocalDir
		
	fi
	echo "$echoPrefix: finish clonning $gitBranch, branch is in $getBranchFromGitRetVal"
}

getHadoopFromLocal()
{
	echo "$echoPrefix: getting hadoop from locally from $LOCAL_HADOOP_DIR"
	if [ -z "$LOCAL_HADOOP_DIR" ];then
		echo "$echoPrefix: LOCAL_HADOOP_DIR must be set when working with local hadoop" | tee $ERROR_LOG
		exit $EEC1
	fi
	headline="Running hadoop from local directory"

	scp -r $LOCAL_HADOOP_DIR $setupEnvDir >> $DEV_NULL_PATH
	getHadoopRetVal=$setupEnvDir/`basename $LOCAL_HADOOP_DIR`
}

buildRpmGit()
{
	local gitMasterTempDir=$1
	local rpmBuild=$gitMasterTempDir/$MASTER_RPM_BUILD_RELATIVE_PATH
	echo "$echoPrefix: building the rpm from $rpmBuild"
	bash $rpmBuild > $STATUS_DIR/buildRpm.txt #building rpm
	if ((`cat $STATUS_DIR/buildRpm.txt | grep -c "SUCCESS: Your RPM is under"` != 1));then
		echo "$echoPrefix: failed to build the rpm" | tee $ERROR_LOG
		exit $EEC1
	fi
}

getUda()
{
	local gitProject=$1
	local gitBranch=$2
	local localBranchDir=$3
	if (($gitUdaFlag==0));then
		getBranchFromGit "$gitProject" "$gitBranch" "$localBranchDir"
		gitUdaFlag=1
		getUdaRetVal=$getBranchFromGitRetVal
		gitMasterTempDirForNextTime=$getUdaRetVal
	else
		getUdaRetVal=$gitMasterTempDirForNextTime
	fi
}

setCoreDir()
{
	local node=$1
	local fullCorePattern=$CORES_DIR/$CORES_PATTERN
	local kernelCorePattern="$KERNEL_CORE_PATTERN_PROPERTY = $fullCorePattern"
	
	echo "$echoPrefix: setting core-pattern"
	sudo ssh $node "echo $fullCorePattern | sudo tee $PROC_CORE_PATTERN_PATH"
	# managing the core files location
	local kernelLineStatus=`ssh $node "grep -c $KERNEL_CORE_PATTERN_PROPERTY $SYSCTL_PATH"`
	local tempSysctl=$TMP_DIR/`basename $SYSCTL_PATH`
	if (($kernelLineStatus == 1));then # replacing the current line
		sudo ssh $node "sed '/kernel.core_pattern/ c $kernelCorePattern' $SYSCTL_PATH > $tempSysctl; mv -f $tempSysctl $SYSCTL_PATH"
	elif (($kernelLineStatus == 0));then # adding a new line
		sudo ssh $node "sed '/# Useful for debugging multi-threaded applications/ a $kernelCorePattern' $SYSCTL_PATH > $tempSysctl; mv -f $tempSysctl $SYSCTL_PATH"
	else
		echo "$echoPrefix: problematic $SYSCTL_PATH file - contains more duplicate kernel.core_pattern property" | tee $ERROR_LOG
		exit $EEC1
	fi
}

setHugePages()
{
	local node=$1

	echo "$echoPrefix: setting huge pages"
	local showHugePagesCmd="grep HugePages_Total /proc/meminfo"
	local showShmMaxCmd="cat /proc/sys/kernel/shmmax"
	local lastHugePagesCount=`ssh $node $showHugePagesCmd | awk '{print $2}'`
	local lastShmMax=`ssh $node $showShmMaxCmd`
	local shmMaxNeeded=""
	
	if (($HUGE_PAGES_COUNT == 0));then
		shmMaxNeeded=$SYSTEM_DEFAULT_SHM_MAX_SIZE
	else
		hugePageSizeKb=`ssh $node grep Hugepagesize /proc/meminfo | awk '{print $2}'`
		shmMaxNeeded=$((HUGE_PAGES_COUNT*hugePageSizeKb*1024))
	fi
	sudo ssh $node "echo $shmMaxNeeded > /proc/sys/kernel/shmmax; echo $HUGE_PAGES_COUNT > /proc/sys/vm/nr_hugepages"
	local newHugePageCount=`ssh $node $showHugePagesCmd | awk '{print $2}'`
	local newShmMax=`ssh $node $showShmMaxCmd`
	echo "$echoPrefix: huge pages are $newHugePageCount, shmmax is $newShmMax"
	
	echo "sudo echo $lastHugePagesCount > /proc/sys/vm/nr_hugepages;
		echo $lastShmMax > /proc/sys/kernel/shmmax;
		echo `eval $showHugePagesCmd`, shmmax is `eval $showShmMaxCmd`" >> $slavesExitScript
		
	restartClusterConfiguration=1
}

patchToVanilla()
{	
	local vanillaHadoop=$1
	local patchFile=$2
	local pOption=$3

	echo "$echoPrefix: patching hadoop"
	getUda "$DEFAULT_GIT_MASTER_DIR" "$GIT_BRANCH" "$udaBaseDir"
	local patchFilePath=$getUdaRetVal/$MASTER_PLUGINS_RELATIVE_PATH/$patchFile

	cd $vanillaHadoop
	patch $pOption < $patchFilePath
	patchStatus=$?
	cd -

	if (($patchStatus != 0));then
		echo "$echoPrefix: patching with $vanillaHadoop failed" | tee $ERROR_LOG
		exit $EEC1
	else
		echo "$echoPrefix: patching with $vanillaHadoop succeeded"
	fi
}

editBuildFile()
{
	local vanillaHadoop=$1
	local fs=$2
	local vanillaBuildFile=$vanillaHadoop/build.xml
	local tempBuildFile=$TMP_DIR/build.xml
	
	newBuildLine=`grep 'target name="package"' $vanillaBuildFile | awk -v fieldSup="$fs" 'BEGIN {FS=fieldSup} {print $1 $2}'`
	
	insertRowIntoFile "target name=\"package\"" "$newBuildLine" "$vanillaBuildFile"
	
	sed "/target name=\"package\"/ c $newBuildLine" $vanillaBuildFile > $tempBuildFile
	cat $tempBuildFile > $vanillaBuildFile
}

manageHadoop()
{
	if [[ $HADOOP_DIRNAME == "hadoop-1.1.2-vanilla" ]];then
		tar -xzf hadoop-1.1.2-vanilla.tar.gz
		hadoopHome="$hadoopHome/hadoop-1.1.2-vanilla"
		editBuildFile "$hadoopHome" "docs, "
	elif [[ $HADOOP_DIRNAME == "hadoop-1.1.0-patched-v2" ]];then
		editBuildFile "$hadoopHome" "docs, cn-docs, "
	fi
}

manageLzoResources()
{
	local node=$1
	local missingResources=""
	local checkIncludeResources=`ssh $node "if [[ ! -d $LZO_USR_INCLUDE_DIR ]];then echo MISS;fi"`
	if [[ -n $checkIncludeResources ]];then
		missingResources="$missingResources $LZO_USR_INCLUDE_DIR"
	else
		checkUseLibResources=`ssh $node "for file in $LZO_USR_LIB_FILES;do if [[ ! -f $LZO_USR_LIB_DIR/$file ]];then export MR=${MR}_${LZO_USR_LIB_DIR}/$file; fi; done; echo $MR"`
		if [[ -n $checkUseLibResources ]];then
			missingResources="$missingResources $checkUseLibResources"
		fi
	fi
	
	if [[ -n $missingResources ]];then
		echo "$echoPrefix: lzo resources missing: $missingResources" | tee $ERROR_LOG
		exit $EEC1
	fi
	
	local lzoLocalResourcesDir=$TMP_DIR/$LZO_LOCAL_RESOURCES_DIR_NAME
	ssh $node mkdir $lzoLocalResourcesDir
	scp -r $LZO_RESOURCE_FILES_PATH/* $node:$lzoLocalResourcesDir >> $DEV_NULL_PATH
	manageLzoResourcesFlagRetVal=$lzoLocalResourcesDir
	echo REASOURCES EXISTS!
}

insertRowIntoFile()
{
	local row="$1"
	local indicator="$2"
	local destFile="$3"
	local forceNewRow="$4"
	
	local tmpFile=$TMP_DIR/$TEMP_SUFFIX

	if [[ -n "$forceNewRow" ]] || [ ! -e $destFile ] || ((`grep -c "$indicator" $destFile` == 0));then
		echo "$row" >> "$destFile"
	else
		sed "/$indicator/ c $row" $destFile > $tmpFile
		mv $tmpFile $destFile
	fi
}
	
manageUdaJarLinking()
{
	local machine=$1
	if (($YARN_HADOOP_FLAG == 1));then
		udaJarLinkDir=$myHadoopHome/$HADOOP_RESOURCES_DIR
		links=`ssh $machine find $udaJarLinkDir -name $RPM_JAR`
		if [[ -n $links ]];then
			ssh $machine rm -rf $links
		fi
		echo "$echoPrefix: ssh $machine ln -s $UDA_RESOURCES_DIR/$RPM_JAR $udaJarLinkDir"
		ssh $machine ln -s $UDA_RESOURCES_DIR/$RPM_JAR $udaJarLinkDir
	fi
}

manageRpmInstallation()
{
	local machine=$1
	local rpm=$2
	if ssh $machine rpm -qa | grep -q libuda; then
		echo "$echoPrefix: uninstalling the existing RPM"
		sudo ssh $machine rpm -e libuda;
	fi		
	echo "$echoPrefix: installing RPM: $rpm"
	sudo ssh $machine rpm -ivh $rpm
	if (($? != 0)); then
			echo "$echoPrefix: error occured when installing RPM on $machine" | tee $ERROR_LOG
			exit $EEC1
	fi
	installedRpm=`sudo ssh $machine rpm -iq libuda`
	echo "$echoPrefix: the installed RPM is $installedRpm"	
}

getLinkRealPath()
{
	local link=$1
	getLinkRealPath_retVal=$link
	local realPath=`ls -l $link | awk -v fieldSup="$LINK_INDICATOR" 'BEGIN{FS=fieldSup};{print $2}'`
	if [[ -n $realPath ]];then
		getLinkRealPath_retVal=$realPath	
	fi
}

echoPrefix=`eval $ECHO_PATTERN`
gitUdaFlag=0
manageLzoResourcesFlag=0

headline=""
urlLine=""
restartClusterConfiguration=""
udaBaseDir=$BASE_DIR
setupEnvDir=$ENV_DIR
covfileDirForTests=$CODE_COVERAGE_INTERMEDIATE_DIR

envSourceFile=$setupEnvDir/$ENV_EXPORTS_FILENAME
source $envSourceFile

slavesExitScript=$STATUS_DIR/slavesExitScript.sh
echo -n "" > $slavesExitScript

# preparing the master

if (($BUILD_SERVER_FLAG==1));then
	hadoopHome=$setupEnvDir/${HADOOP_HOME_DIR_PREFIX}${HADOOP_VERSION}
	mkdir -p $hadoopHome
	echo "$echoPrefix: tar -xf $LOCAL_HADOOP_DIR -C $hadoopHome"
	tar -xf $LOCAL_HADOOP_DIR -C $hadoopHome
	filesCount=`ls $hadoopHome | grep -c ""`
	if (($filesCount==1));then
		nestedDir="$hadoopHome/*"
		mv $nestedDir/* $hadoopHome
	fi
else
	if (($CO_FLAG==1));then
		getBranchFromGit "$DEFAULT_GIT_HADOOPS_DIR" "$HADOOP_DIRNAME" "$setupEnvDir"
		hadoopHome=$getBranchFromGitRetVal
	else  # in case we're running a totaly-build and ready hadoop from NFS
		getHadoopFromLocal
		hadoopHome=$getHadoopRetVal
	fi
	manageHadoop
fi

if (($PATCH_FLAG==1));then
	patchToVanilla $hadoopHome $PATCH_NAME "-p0 -s"
	newHadoopHome=${hadoopHome}$PATCHED_HADOOP_SUFFIX
	mv $hadoopHome $newHadoopHome
	hadoopHome=$newHadoopHome
fi			

if (($BUILD_FLAG==1)) || (($PATCH_FLAG==1))
then
	buildOptions="-D${ANT_NATIVE_PROP}=true"
	echo "$echoPrefix: Compiling with native!"	

	cd $hadoopHome
	buildCmd="$ANT_PATH -D${ANT_JAVA_PROP}=$JAVA_HOME $buildOptions $ANT_OPTIONS"

	echo "$echoPrefix: $buildCmd" 
	eval $buildCmd > $STATUS_DIR/buildHadoop.txt	
	buildStatus=`cat $STATUS_DIR/buildHadoop.txt | grep -c "BUILD SUCCESSFUL"`

	if (($buildStatus == 0));then 
		echo "$echoPrefix: BUILD FAILED!" | tee $ERROR_LOG
		exit $EEC1
	fi
	
	if [[ $HADOOP_DIRNAME == "hadoop-1.1.2-vanilla" ]] || [[ $HADOOP_DIRNAME == "hadoop-1.1.0-patched-v2" ]];then
		echo "$echoPrefix: hadoop version is $HADOOP_DIRNAME"  #building
		snapshotFolder=`find $hadoopHome/build -maxdepth 1 -mindepth 1 -type d | grep "SNAPSHOT"`
		matchCount=`echo $snapshotFolder | grep -c "SNAPSHOT"`
		if (($matchCount != 1));then
			echo "error: found $matchCount SNAPSHOT folders" | tee $ERROR_LOG
			exit $EEC1
		fi
        rm -f $hadoopHome/hadoop*examples*.jar
        rm -f $hadoopHome/hadoop*test*.jar
		echo "$echoPrefix: copying snapshot folter content into hadoop-home"
		cp -r $snapshotFolder/* $hadoopHome/
	fi

	headline="Daily Smoke Test of revision $revision"
	urlLine="from $SVN_HADOOP";
fi

myHadoopHome=$hadoopHome
if [[ $myHadoopHome == "/" ]];then
	echo "$echoPrefix: MY_HADOOP_HOME is / !!" | tee $ERROR_LOG
	exit $EEC1
fi

hadoopConfDir=$myHadoopHome/$HADOOP_CONF_DIR_RELATIVE_PATH
hadoopEnv=$hadoopConfDir/$HADOOP_ENVS_SCRIPT_NAME

javaHomeLine="export JAVA_HOME=$JAVA_HOME"
insertRowIntoFile "$javaHomeLine" "export JAVA_HOME=" "$hadoopEnv"
if (($YARN_HADOOP_FLAG == 1));then
	forcingNewRowClasspath="1"
	yarnEnv=$hadoopConfDir/$YARN_ENVS_SCRIPT_NAME
	insertRowIntoFile "$javaHomeLine" "export JAVA_HOME=" "$yarnEnv"
	hadoopClientOptsLine="export HADOOP_CLIENT_OPTS=\"\${HADOOP_CLIENT_OPTS} -Djava.net.preferIPv4Stack=true\""
	#insertRowIntoFile "$hadoopClientOptsLine" "export HADOOP_CLIENT_OPTS=" "$yarnEnv"
	insertRowIntoFile "$hadoopClientOptsLine" "export HADOOP_CLIENT_OPTS=" "$hadoopEnv"
	hadoopHomeLine="export HADOOP_HOME=$myHadoopHome"
	insertRowIntoFile "$hadoopHomeLine" "export HADOOP_HOME=" "$hadoopEnv"
else
	forcingNewRowClasspath=""
	hadoopOptsLine="export HADOOP_OPTS=\"\${HADOOP_OPTS} -Djava.net.preferIPv4Stack=true -DudaHostName=\`hostname\`-${INTERFACE} \""
	insertRowIntoFile "$hadoopOptsLine" "export HADOOP_OPTS=" "$hadoopEnv"
fi
hadoopClasspathLine="export HADOOP_CLASSPATH=${HADOOP_CLASSPATH}${RPM_JAR}"
insertRowIntoFile "$hadoopClasspathLine" "export HADOOP_CLASSPATH=" "$hadoopEnv" "$forcingNewRowClasspath"

maxProcLimitLine="ulimit -u 32000"
insertRowIntoFile "$maxProcLimitLine" "export HADOOP_CLASSPATH=" "$hadoopEnv" "$forcingNewRowClasspath"

if [[ $COMPRESSION == "Lzo" ]]; then
	manageLzoResources $MASTER
	manageLzoResourcesFlag=1	
	lzoLocalResourcesDir=$manageLzoResourcesFlagRetVal

	echo "$echoPrefix: sed /export HADOOP_CLASSPATH=/ c export HADOOP_CLASSPATH=${HADOOP_CLASSPATH}:${RPM_JAR}${LZO_JAR} $myHadoopHome/$HADOOP_CONF_DIR_RELATIVE_PATH/hadoop-env2.sh > $myHadoopHome/$HADOOP_CONF_DIR_RELATIVE_PATH/hadoop-env.sh"
	sed "/export HADOOP_CLASSPATH=/ c export HADOOP_CLASSPATH=${HADOOP_CLASSPATH}${RPM_JAR}:${LZO_JAR}" $myHadoopHome/$HADOOP_CONF_DIR_RELATIVE_PATH/hadoop-env.sh > $myHadoopHome/$HADOOP_CONF_DIR_RELATIVE_PATH/hadoop-env2.sh
	
	echo "$echoPrefix: cat $myHadoopHome/$HADOOP_CONF_DIR_RELATIVE_PATH/hadoop-env2.sh"
	mv $myHadoopHome/$HADOOP_CONF_DIR_RELATIVE_PATH/hadoop-env2.sh  $myHadoopHome/$HADOOP_CONF_DIR_RELATIVE_PATH/hadoop-env.sh
	if [[ `cat $myHadoopHome/$HADOOP_CONF_DIR_RELATIVE_PATH/hadoop-env.sh` == *JAVA_LIBRARY_PATH* ]]; then
		echo "$echoPrefix: Changing JAVA_LIBRARY_PATH in hadoop-env"
		sed "/export JAVA_LIBRARY_PATH=/ c export JAVA_LIBRARY_PATH=$lzoLocalResourcesDir" $myHadoopHome/$HADOOP_CONF_DIR_RELATIVE_PATH/hadoop-env.sh > $myHadoopHome/$HADOOP_CONF_DIR_RELATIVE_PATH/hadoop-env2.sh
		#mv $myHadoopHome/$HADOOP_CONF_DIR_RELATIVE_PATH/hadoop-env2.sh  $myHadoopHome/$HADOOP_CONF_DIR_RELATIVE_PATH/hadoop-env.sh
	else
		echo "$echoPrefix: there's no JAVA_LIBRARY_PATH exported in hadoop-env.sh "
		echo "export JAVA_LIBRARY_PATH=$lzoLocalResourcesDir" >> $myHadoopHome/$HADOOP_CONF_DIR_RELATIVE_PATH/hadoop-env.sh
	fi
elif [[ $COMPRESSION == "Snappy" ]]
then
	for machine in $ENV_MACHINES_BY_SPACES
	do
		if ((`ssh $machine rpm -qa | grep -c snappy` == 0));then
			echo "$echoPrefix: installing snappy: ssh $machine sudo yum -y install $SNAPPY_PACKAGES"
			ssh $machine sudo yum -y install $SNAPPY_PACKAGES	
		else 
			echo "$echoPrefix: snappy is installed on $machine";
		fi
	done

	if [[ -n $HADOOP_NATIVE_RELATIVE_DIR ]]
	then
		hadoopRelativeDir=$hadoopHome/$HADOOP_NATIVE_RELATIVE_DIR
		for dir in `ls $hadoopRelativeDir`;do
			echo "$echoPrefix: scp ${SNAPPY_LIB_PATH}* $hadoopRelativeDir/$dir/"
			scp ${SNAPPY_LIB_PATH}* $hadoopRelativeDir/$dir/
		done
	fi
fi	

if (($CODE_COVE_FLAG==1)); then
	# setting COVFILE in hadoop-env
	covfileForTestsName=${ENV_FIXED_NAME}${CODE_COVERAGE_FILE_SUFFIX}
	covfileForTests=$covfileDirForTests/$covfileForTestsName
	envFile="$myHadoopHome/$HADOOP_CONF_DIR_RELATIVE_PATH/hadoop-env.sh"
	covfileRow="export COVFILE=$covfileForTests"
	covfileIndicator="export COVFILE="
	insertRowIntoFile "$covfileRow" "$covfileIndicator" "$envFile"
fi

echo -e \\n
echo "$echoPrefix: MY_HADOOP_HOME is $myHadoopHome"
sudo chown -R $USER $myHadoopHome
if (($? != 0));then
	echo "$echoPrefix: error occured when setting the hadoop-directory" | tee $ERROR_LOG
	exit $EEC1
fi

echo -e \\n

if (($RPM_FLAG==1))
then	
	if (($UDA_PLACE_TYPE==0));then # getting a local and built rpm
		echo "$echoPrefix: installing the rpm locally from $LOCAL_UDA_DIR"
		getLinkRealPath $UDA_PLACE_VALUE
		currentRpm=$getLinkRealPath_retVal
		if (($CODE_COVE_FLAG==1)) && (($BUILD_SERVER_FLAG==1)); then
			echo "$echoPrefix: cp $BUILD_SERVER_PRODUCTS_DIR/$BUILD_SERVER_COVFILE_NAME $CODE_COVERAGE_TEMPLATE_COVFILE_DIR"
			cp $BUILD_SERVER_PRODUCTS_DIR/$BUILD_SERVER_COVFILE_NAME $CODE_COVERAGE_TEMPLATE_COVFILE_DIR
			
			codeCoverageMasterDir=$BUILD_SERVER_DEFAULT_BRANCH
		fi
	else # needs to build the rpm
		if (($UDA_PLACE_TYPE==1));then # getting branch from git
			# getting the master dir from git if needed
			getUda "$DEFAULT_GIT_MASTER_DIR" "$GIT_BRANCH" "$udaBaseDir"
			currentUdaDir=$getUdaRetVal
		elif (($UDA_PLACE_TYPE==2));then # getting a local branch (pre-cloned from git)
			currentUdaDir=$UDA_PLACE_VALUE
		else
			echo "$echoPrefix: UDA_PLACE_TYPE have unexpected value of $UDA_PLACE_TYPE" | tee $ERROR_LOG
			exit $EEC1
		fi
		echo "$echoPrefix: start building the rpm from $currentUdaDir"
		
		if (($CODE_COVE_FLAG==1)); then
			covfileForBuildName=${CODE_COVERAGE_TEMPLATE_COVFILE_FILE_NAME}${CODE_COVERAGE_FILE_SUFFIX}
			covfileForBuild=$currentUdaDir/$covfileForBuildName
			export COVFILE=$covfileForBuild # different path from the hadoop-env's COVFILE
			echo "$echoPrefix: tunring  on: cov01 -1"
			cov01 --on
			echo "$echoPrefix: tunring Bullseye flag stat on: cov01 -s"
			cov01 --status
			
			codeCoverageMasterDir=$GIT_BRANCH # GIT_BRANCH eqaul to git branch name or to BUILD_SERVER_DEFAULT_BRANCH (look at parseCluster.awk)
		else
			cov01 --off # for case that the bullseye left turned-on on the machine 
		fi
		
		buildRpmGit $currentUdaDir
		cd ~
		cd $RPMBUILD_DIR
		currentRpm=`pwd`/`ls -t | grep -m 1 ""`
		
		if (($CODE_COVE_FLAG==1)); then
			echo "cov01 --off # bullseye Flag stat"
			cov01 --off
			sudo chmod $DIRS_PERMISSIONS $covfileForBuild
			mv $covfileForBuild $CODE_COVERAGE_TEMPLATE_COVFILE_DIR
			unset COVFILE # safety measurment for avoiding conflict when exporting the COVFILE in the hadop-env
		fi
	fi
	
	currentRpmVersion=`echo $currentRpm | awk 'BEGIN{FS="libuda-"} {print $2}' | awk 'BEGIN{FS="."} {if ($4 ~ /[a-zA-Z]+/){print $1 "." $2 "." $3 "." $4 "." $5}else{print $1 "." $2 "." $3 "." $4}}'` # according to the format in BUILD.README file
	shortFormatVersion=`echo $currentRpmVersion | awk 'BEGIN{FS="."} {print $1 "." $2 "." $3}' | awk 'BEGIN{FS="-"} {print $1}'`
	echo "$echoPrefix: installing the rpm $currentRpm. parsed version is: $currentRpmVersion, short version is: $shortFormatVersion"
	manageRpmInstallation $MASTER $currentRpm
fi	

manageUdaJarLinking $MASTER

if (($CHANGE_MACHINE_NAME_FLAG == 1));then
	newMachineNameSuffix="-${INTERFACE}"
else
	newMachineNameSuffix=""
fi

bash $SCRIPTS_DIR/functionsLib.sh "set_hostnames" "$MASTER" "${MASTER}${newMachineNameSuffix}" 

echo "$echoPrefix: killing all java processes"
sudo pkill -9 java

if (($CODE_COVE_FLAG==1)); then
	echo "$echoPrefix: cp $CODE_COVERAGE_TEMPLATE_COVFILE_DIR/*$CODE_COVERAGE_FILE_SUFFIX $covfileForTests"
	cp $CODE_COVERAGE_TEMPLATE_COVFILE_DIR/*$CODE_COVERAGE_FILE_SUFFIX $covfileForTests
fi

setCoreDir $MASTER

# preparing the slaves
for slave in $SLAVES_BY_SPACES
do
	echo -e \\n\\n
	echo "$echoPrefix: $slave:"
	
	if [[ $slave == $MASTER ]];then
		echo "$echoPrefix: node $slave is both master and slave. it already set"
		continue
	fi
		
	echo "$echoPrefix: killing all java processes"
	sudo ssh $slave pkill -9 java
		
	echo "$echoPrefix: copying hadoop"
	sudo ssh $slave mkdir -p $myHadoopHome
	sudo scp -r $myHadoopHome/* $slave:$myHadoopHome > $DEV_NULL_PATH # the redirection is just to ignore the scp long output
	sudo ssh $slave sudo chown -R $USER $myHadoopHome
	
	if (($RPM_FLAG==1));then
		manageRpmInstallation $slave $currentRpm
	fi

	manageUdaJarLinking $slave
	bash $SCRIPTS_DIR/functionsLib.sh "set_hostnames" "$slave" "${slave}${newMachineNameSuffix}" 
	
	if (($CODE_COVE_FLAG==1)); then
	echo "$echoPrefix: copying covfile: scp $covfileForTests $slave:$covfileForTests"
		scp $covfileForTests $slave:$covfileForTests 
	fi
	
	if (($manageLzoResourcesFlag==1));then
		manageLzoResources $slave
	fi		
	setCoreDir $slave
	if (($HUGE_PAGES_FLAG==1));then
		setHugePages $slave
	fi			
done
echo -e \\n\\n

echo "$echoPrefix: finishing setting-up the cluster, under $myHadoopHome"

echo "
	#!/bin/sh
	`cat $envSourceFile`
	export MY_HADOOP_HOME='$myHadoopHome/$HADOOP_HOME_RELATIVE_DIR'
	#export HADOOP_CONF_DIR='$MY_HADOOP_HOME/$HADOOP_CONF_DIR_RELATIVE_PATH'
	export HEADLINE='$headline'
	if [[ -n '$currentRpm' ]];then
		export INSTALLED_RPM='$currentRpm'
		export RPM_VERSION='$currentRpmVersion'
		export VERSION_SHORT_FORMAT='$shortFormatVersion'
	fi
	if [[ -n '$codeCoverageMasterDir' ]];then
		export BULLSEYE_BRANCH_NAME='$codeCoverageMasterDir'
	fi
	#if [[ -n '$hadoopConfDir' ]];then
		export HADOOP_CONF_DIR='$hadoopConfDir'
	#fi
	#export CURRENT_DATE='$CURRENT_DATE'
	export UDA_CORES_DIR='$udaCores'
	export EXIT_SCRIPTS_SLAVES='$slavesExitScript'
	export RESTART_CLUSTER_CONF_FLAG=$restartClusterConfiguration
	#export FIRST_MTT_SETUP_FLAG=$firstMttSetupFlag
	export CODE_COVERAGE_FILE='$covfileForTests'
" > $SOURCES_DIR/setupClusterExports.sh
