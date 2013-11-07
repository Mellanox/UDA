#!/bin/bash

echoPrefix=`eval $ECHO_PATTERN`	
clusterEnv=$1

unset PRE_REQ_SETUP_FLAGS
envDir=$BASE_DIR/$clusterEnv

envExportsFile=$envDir/$ENV_EXPORTS_FILENAME
source $envExportsFile
echo "$echoPrefix: sourcing $envExportsFile"
preReqExports=
source $envDir/$ENV_PRE_REQ_EXPORTS_FILENAME
echo "$echoPrefix: sourcing $envDir/$ENV_PRE_REQ_EXPORTS_FILENAME"
allSetupTestsExports=$TESTS_CONF_DIR/$ENV_FIXED_NAME/allSetupsExports.sh
source $allSetupTestsExports
echo "$echoPrefix: sourcing $allSetupTestsExports"

hadoopCommandsScript=$SCRIPTS_DIR/$HADOOP_SPECIFIC_SCRIPT_NAME
echo "$echoPrefix: hadoop type is $HADOOP_TYPE. sourcing $hadoopCommandsScript" 
source $hadoopCommandsScript

statusDir=$envDir/$STATUS_DIR_NAME
tmpDir=$envDir/$TMP_DIR_NAME
codeCoverageIntermediateDir=""
if (($CODE_COVE_FLAG==1)); then
	codeCoverageIntermediateDir=$envDir/$CODE_COVERAGE_ENV_LOCAL_DIR_NAME
fi

if ! mkdir -p $TMP_DIR_LOCAL_DISK;then
	echo "$echoPrefix: failing creating TMP_DIR_LOCAL_DISK on $TMP_DIR_LOCAL_DISK"
	exit $EEC1
fi
rm -rf $TMP_DIR_LOCAL_DISK/*

errorLog=$envDir/runtimeErrorLog.txt
echo -n "" >  $errorLog

for machine in $ENV_MACHINES_BY_SPACES
do
	sudo ssh $machine mkdir -p $tmpDir $statusDir $codeCoverageIntermediateDir
	sudo ssh $machine chown -R $USER $tmpDir $statusDir $codeCoverageIntermediateDir
	# makeing and checking the swapoff
	echo "$echoPrefix: disabling swapiness on $machine"
	sudo ssh $machine sudo $SWAPOFF_PATH -a
done

echo "$echoPrefix: cheching pre-requests: bash $SCRIPTS_DIR/preReq.sh $PRE_REQ_SETUP_FLAGS"
bash $SCRIPTS_DIR/preReq.sh $PRE_REQ_SETUP_FLAGS
if (($? == $EEC3));then 
	exit $EEC3
fi	

bash $SCRIPTS_DIR/dfsManager.sh -dp

currentDate=`eval $CURRENT_DATE_PATTERN`

echo "`cat $envExportsFile`
	`cat $hadoopCommandsScript`
	`cat $allSetupTestsExports`
	export ENV_DATE='$currentDate'
	export ENV_NAME='$clusterEnv'
	export ENV_DIR='$envDir'
	export STATUS_DIR='$statusDir'
	export TMP_DIR='$tmpDir'
	export CODE_COVERAGE_INTERMEDIATE_DIR='$codeCoverageIntermediateDir'
	export ERROR_LOG='$errorLog'
" > $SOURCES_DIR/prepareSetupExports.sh

