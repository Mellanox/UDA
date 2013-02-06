#!/bin/bash

echoPrefix=`eval $ECHO_PATTERN`
freeSpaceFlag=`sudo df -h | grep -m 1 "\% \/" | grep 100\%`
if [[ $freeSpaceFlag != "" ]];then
	echo -e "$echoPrefix: there is no enouth place on the disk" | tee $ERROR_LOG
	exit $EEC1
fi

currentConfsDir=$CONF_FOLDER_DIR/${CONFS_DIR_NAME}_${CURRENT_DATE}

if [ -d $currentConfsDir ];then
	currentConfsDir=${currentConfsDir}_`date +"%s"`
	echo "$echoPrefix: $currentConfsDir already exist. tring create ${currentConfsDir}"
	if ! mkdir ${currentConfsDir};then
		echo "$echoPrefix: failling to create ${currentConfsDir}" | tee $ERROR_LOG
		$EEC1
	fi
else
	echo "$echoPrefix: creating test folder at $currentConfsDir"
	if ! mkdir -p $currentConfsDir;then
		echo "$echoPrefix: failling to create $currentConfsDir" | tee $ERROR_LOG
		$EEC1
	fi
fi

echo "$echoPrefix: building the tests-files at $currentConfsDir"

# 	after running parseTests.awk the execution folders will include:
# 	one for the whole session: script named "setupsExports.sh", that contains the needed exports
# 	one each cluster setup: script named "general.sh", that contains the needed exports
#	for every test: exports-file and (if needed) configuration files (XMLs)

awk -v confsFolderDir=$currentConfsDir -v setupPrefix=$SETUP_DIR_PREFIX -v testDirPrefix=$TEST_DIR_PREFIX -f $SCRIPTS_DIR/parseTests.awk $CSV_FILE 
#/labhome/oriz/backup/CMDpro-3.9.2012/parseTests.awk  $SCRIPTS_DIR/parseTests.awk
if (($?!=0));then
	echo "$echoPrefix: error during executing the parser script" | tee $ERROR_LOG
	exit $EEC1
fi

sudo chgrp -R $GROUP_NAME $currentConfsDir
sudo chown -R $USER $currentConfsDir
chmod -R $DIRS_PERMISSIONS $currentConfsDir
# using the general exports of the tests
source $currentConfsDir/setupsExports.sh

if [[ $ERRORS != "" ]];then
	if (($CONFIGURE_FLAG == 0));then
		echo "$echoPrefix: errors has found in the tests-files: $ERRORS" | tee $ERROR_LOG
	else
		echo "$echoPrefix: errors has found in the tests-files" | tee $ERROR_LOG
	fi
    exit $EEC1
fi

echo "
	#!/bin/sh
	source $currentConfsDir/setupsExports.sh
	export CONFS_DIR=$currentConfsDir
" > $TMP_DIR/configureExports.sh
