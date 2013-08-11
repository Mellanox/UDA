#!/bin/bash

echoPrefix=`eval $ECHO_PATTERN`	
clusterEnv=$1

unset PRE_REQ_SETUP_FLAGS
envDir=$BASE_DIR/$clusterEnv
source $envDir/envExports.sh
echo "$echoPrefix: sourcing $envDir/envExports.sh"
source $envDir/preReqSetup.sh
echo "$echoPrefix: sourcing $envDir/preReqSetup.sh"

statusDir=$envDir/$STATUS_DIR_NAME
tmpDir=$envDir/$TMP_DIR_NAME
codeCoverageIntermediateDir=""
if (($CODE_COVE_FLAG==1)); then
	codeCoverageIntermediateDir=$envDir/$CODE_COVERAGE_ENV_LOCAL_DIR_NAME
fi

if ! sudo mkdir -p $TMP_DIR_LOCAL_DISK;then
	exit $EEC1
fi
sudo chown -R $USER $TMP_DIR_LOCAL_DISK
rm -rf $TMP_DIR_LOCAL_DISK/*

errorLog=$envDir/runtimeErrorLog.txt
echo -n "" >  $errorLog

for machine in $MASTER $SLAVES_BY_SPACES
do
	sudo ssh $machine mkdir -p $tmpDir $statusDir $codeCoverageIntermediateDir
	sudo ssh $machine chown -R $USER $tmpDir $statusDir $codeCoverageIntermediateDir
	# makeing and checking the swapoff
	echo "$echoPrefix: disabling swap is off"
	sudo ssh $machine sudo $SWAPOFF_PATH -a
done

preReqFlags=$PRE_REQ_SETUP_FLAGS
if [[ "$preReqFlags" == "-" ]];then
	preReqFlags=$DEFAULT_PRE_REQ_SETUP_FLAGS
fi

echo "$echoPrefix: cheching pre-requests: bash $SCRIPTS_DIR/preReq.sh $preReqFlags"
bash $SCRIPTS_DIR/preReq.sh $preReqFlags
if (($? == $EEC3));then 
	exit $EEC3
fi	
currentDate=`eval $CURRENT_DATE_PATTERN`

echo "`cat $envDir/envExports.sh`
	export ENV_DATE='$currentDate'
	export ENV_NAME='$clusterEnv'
	export ENV_DIR=$envDir
	export STATUS_DIR='$statusDir'
	export TMP_DIR='$tmpDir'
	export CODE_COVERAGE_INTERMEDIATE_DIR='$codeCoverageIntermediateDir'
	export ERROR_LOG='$errorLog'
" > $SOURCES_DIR/prepareSetupExports.sh

