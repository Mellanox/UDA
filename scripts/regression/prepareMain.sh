#!/bin/bash

echoPrefix=`eval $ECHO_PATTERN`
currentDate=`eval $CURRENT_DATE_PATTERN`

inputFlag=1

testsConfDir=$BASE_DIR/$TESTS_CONF_DIR_NAME
if ! sudo mkdir -p $testsConfDir;then
	exit $EEC1
fi
rm -rf $BASE_DIR/*

if ! sudo mkdir -p $SOURCES_DIR;then
	exit $EEC1
fi

configurtionFilesDir=$BASE_DIR/$CONFIGURATION_FILES_DIR_NAME
if ! sudo mkdir -p $configurtionFilesDir;then
	exit $EEC1
fi
	
if ! sudo mkdir -p $TMP_DIR_LOCAL_DISK;then
	exit $EEC1
fi
rm -rf $TMP_DIR_LOCAL_DISK/*

errorLog=$BASE_DIR/runtimeErrorLog.txt
echo -n "" >  $errorLog

sudo chown -R $USER $BASE_DIR

# CHECKING PRE-REQs

# checking the master's OS-disk's free space
echo "$echoPrefix: cheching pre-requests: bash $SCRIPTS_DIR/preReq.sh -i"
bash $SCRIPTS_DIR/preReq.sh -i
if (($? == $EEC3));then 
	exit $EEC3
fi	

echo "
	#!/bin/sh
	export CURRENT_DATE='$currentDate'
	export ERROR_LOG='$errorLog'
	export INPUT_FLAG=$inputFlag
	export ENVS_CONF_DIR='$envDir'
	export TESTS_CONF_DIR='$testsConfDir'
	export CONFIGURATION_FILES_DIR='$configurtionFilesDir'
" > $SOURCES_DIR/prepareExports.sh
