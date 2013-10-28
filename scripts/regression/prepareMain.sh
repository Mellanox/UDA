#!/bin/bash

echoPrefix=`eval $ECHO_PATTERN`
currentDate=`eval $CURRENT_DATE_PATTERN`

inputFlag=1

testsConfDir=$BASE_DIR/$TESTS_CONF_DIR_NAME
if ! sudo mkdir -p $testsConfDir;then
	exit $EEC1
fi
sudo rm -rf $BASE_DIR/*

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

sudo chown -R $USER $BASE_DIR

errorLog=$BASE_DIR/$ERROR_LOG_FILE_NAME
echo -n "" >  $errorLog
cleanMachineNameFile=$BASE_DIR/$CLEAN_MACHINE_NAME_FILENAME

echo "
	#!/bin/sh
	export CURRENT_DATE='$currentDate'
	export ERROR_LOG='$errorLog'
	export INPUT_FLAG=$inputFlag
	export ENVS_CONF_DIR='$envDir'
	export TESTS_CONF_DIR='$testsConfDir'
	export CONFIGURATION_FILES_DIR='$configurtionFilesDir'
	export CLEAN_MACHINE_NAME_FILE='$cleanMachineNameFile'
" > $SOURCES_DIR/prepareExports.sh
