#!/bin/bash

echoPrefix=`eval $ECHO_PATTERN`
baseDirForParser=$BASE_DIR
sourcesDirForParser=$SOURCES_DIR

cp "$CLUSTER_CONF_FILE" $CONFIGURATION_FILES_DIR

echo "$echoPrefix: building the environments-files at $sourcesDirForParser from $CLUSTER_CONF_FILE"                                      

awk -v baseDir=$baseDirForParser \
 -v sourcesDir=$sourcesDirForParser \
 -v envDirPrefix=$ENV_DIR_PREFIX  \
 -v envExportFileName=$ENV_EXPORTS_FILENAME \
 -v preReqFileName=$ENV_PRE_REQ_EXPORTS_FILENAME \
 -f $SCRIPTS_DIR/parseClusterConf.awk $CLUSTER_CONF_FILE 


if (($?!=0));then
	echo "$echoPrefix: error during executing the cluser-setup's parser-script" | tee $ERROR_LOG
	exit $EEC1
fi

#sudo chgrp -R $GROUP_NAME $sourcesDirForParser
#sudo chown -R $USER $sourcesDirForParser

echo "`cat $sourcesDirForParser/generalEnvExports.sh`" > $SOURCES_DIR/configureClusterExports.sh
