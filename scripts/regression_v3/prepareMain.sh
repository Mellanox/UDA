#!/bin/bash

echoPrefix=$(basename $0)
inputFlag=1

if ! sudo mkdir -p $TMP_DIR;then
	exit $EEC1
fi
sudo chown -R $USER $TMP_DIR
rm -rf $TMP_DIR/*

mkdir $STATUS_DIR

if ! sudo mkdir -p $TMP_DIR_LOCAL_DISK;then
	exit $EEC1
fi
sudo chown -R $USER $TMP_DIR_LOCAL_DISK
rm -rf $TMP_DIR_LOCAL_DISK/*

errorLog=$TMP_DIR/runtimeErrorLog.txt
echo -n "" >  $errorLog

currentDate=`eval $CURRENT_DATE_PATTERN`

echo "
	#!/bin/sh
	export CURRENT_DATE='$currentDate'
	export ERROR_LOG='$errorLog'
	export INPUT_FLAG=$inputFlag
" > $TMP_DIR/prepareExports.sh
