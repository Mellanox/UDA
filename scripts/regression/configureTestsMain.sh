#!/bin/bash

echoPrefix=`eval $ECHO_PATTERN`
envName=$1

confDir=$TESTS_CONF_DIR/$envName # THIS IS THE ONLY EXPORT INTERFERE MOVING THIS SCRIPT NEXT TO THE SETUPS-PARESR
if ! mkdir -p $confDir;then
	echo "$echoPrefix: failed to execute: sudo mkdir -p $confDir" | tee $ERROR_LOG
	exit $EEC1
fi

envSourceFile=$BASE_DIR/$envName/$ENV_EXPORTS_FILENAME
source $envSourceFile

rawConfDir=$CONFIGURATION_FILES_DIR/$envName # THIS IS THE ONLY EXPORT INTERFERE MOVING THIS SCRIPT NEXT TO THE SETUPS-PARESR
if ! mkdir -p $rawConfDir;then
	echo "$echoPrefix: failed to execute: sudo mkdir -p $rawConfDir" | tee $ERROR_LOG
	exit $EEC1
fi

cp "$TEST_CONF_FILE" $rawConfDir

# 	after running parseTests.awk the execution folders will include:
# 	one for the whole session: script named "allSetupsExports.sh", that contains the needed exports
# 	one each cluster setup: script named "general.sh", that contains the needed exports
#	for every test: exports-file and (if needed) configuration files (XMLs)
echo "$echoPrefix: building the tests-files at $confDir from $TEST_CONF_FILE"                                                            
awk -v seed=$RANDOM \
 -v confsFolderDir=$confDir \
 -v setupPrefix=$SETUP_DIR_PREFIX \
 -v testDirPrefix=$TEST_DIR_PREFIX \
 -v yarnFlag=$YARN_HADOOP_FLAG \
 -v interface=$INTERFACE \
 -v master="$MASTER_FOR_XMLS" \
 -v slavesBySpaces="$SLAVES_BY_SPACES" \
 -v udaProviderProp="$UDA_PROVIDER_PROP" \
 -v udaProviderValue="$UDA_PROVIDER_VALUE" \
 -v udaConsumerProp="$UDA_CONSUMER_PROP" \
 -v udaConsumerValue="$UDA_CONSUMER_VALUE" \
 -v udaConsumerProp2="$UDA_CONSUMER_PROP2" \
 -v udaConsumerValue2="$UDA_CONSUMER_VALUE2" \
 -v disableUda="$DISABLE_UDA_FLAG" \
 -f $SCRIPTS_DIR/parseTests.awk "$TEST_CONF_FILE"
if (($?!=0));then
	echo "$echoPrefix: error during executing the parser script" | tee $ERROR_LOG
	exit $EEC1
fi

sudo chgrp -R $GROUP_NAME $confDir
sudo chown -R $USER $confDir
chmod -R $DIRS_PERMISSIONS $confDir
# using the general exports of the tests
source $confDir/allSetupsExports.sh

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
" > $SOURCES_DIR/configureTestsExports.sh
