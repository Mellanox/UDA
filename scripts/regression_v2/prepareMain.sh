#!/bin/bash

echoPrefix=$(basename $0)
inputFlag=1

if ! sudo mkdir -p $TMP_DIR;then
	exit $EEC1
fi
sudo chown -R $USER $TMP_DIR
rm -rf $TMP_DIR/*

errorLog=$TMP_DIR/runtimeErrorLog.txt
echo -n "" >  $errorLog



echo "
	#!/bin/sh
	export ERROR_LOG='$errorLog'
	export INPUT_FLAG=$inputFlag
" > $TMP_DIR/prepareExports.sh
