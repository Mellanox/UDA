#!/bin/bash

## 11 August 2013
## ====================
## Backup Server Script
## ====================
## This script runs on the build backup server and pings the main build server.
## If it finds that the main server is down, it start the build process instead.

# Set backup indication file
INDICATION_FILE="/tmp/BACKUP_RAN_ON_`date +"%d-%m-%Y"`"

# Get .ini configuration file
INI_FILE=$1

# Validate .ini configuration file
if [ -z $1 ]; then
	echo "Error: Missing argument. The .ini configuration file must be given as an argument!"
        touch ${INDICATION_FILE}
        exit 1
elif [ ! -e ${INI_FILE} ]; then
        echo "Error: The .ini configuration file does not exits!"
	touch ${INDICATION_FILE}
        exit 1
elif [ ! -r ${INI_FILE} ]; then
        echo "Error: No read permission for .ini configuration file!"
	touch ${INDICATION_FILE}
        exit 1
else
	MAIN_SERVER=`grep "MAIN_SERVER" $INI_FILE | cut -d "=" -f 2`
	ping -c 3 $MAIN_SERVER > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		# The main server is offline
		echo -e "\nThe main build server is offline!"
		echo -e "\n$Building on backup server..."
		bash ./start.sh "${INI_FILE}"
		touch ${INDICATION_FILE}
		exit 0
	fi
	echo -e "\nThe main build server is online!\n"
	touch ${INDICATION_FILE}
	exit 0
fi
