#!/bin/bash

## 11 August 2013
## =============================
## UDA Hadoop start build Script
## =============================
## This script is scheduled in the server's cron and starts the build process.
## This script logs the build process and e-mails a report upon completion.
## The script gets a reletive path to a configuration file as a parameter.

# Usage Function
usage(){
	echo "UDA/Hadoops Build Process: You must pass an .ini configuration file name as the first parameters."
}

# Check Parameter
if [ -z "$1" ]; then
        usage
        exit 1
fi

# Set .ini configuration file
export INI_FILE=$1

# Validate .ini configuration file
if [ ! -e ${INI_FILE} ]; then
	echo "Error: The .ini configuration file does not exits!"
	exit 1
elif [ ! -r ${INI_FILE} ]; then
        echo "Error: No read permission for .ini configuration file!"
	exit 1
else
	# Configure map functions
	source ./map.sh
	# Configure environment parameters
	source ./configure.sh
	# Check for needed configurations and files
	source ./env_check.sh
	# Clean running environment
	source ./clean.sh

        # Set build log file and dirctory
	LOG_DIR=`cat $INI_FILE | grep "LOG_DIR=" | cut -d "=" -f 2 | sed 's/"//g'`
	mkdir -p ${LOG_DIR}
        LOG=`cat $INI_FILE | grep "LOG_FILE=" | cut -d "=" -f 2 | sed 's/"//g'`

	# Get the latest change date in the db of UDA
	# This is used in case a commit history is shown
	#export latest_uda_date=`cat ${DB_DIR}/latest_uda | cut -d " " -f 1`
	export latest_uda_date=`ls -gGh -p --time-style="+%Y-%m-%d" ${BUILD_POOL}/latest_daily_UDA_${UDA_BRANCH}_rpm | cut -d " " -f 4`

        # Build and log
	source ./build.sh | tee "${LOG_DIR}/${LOG}"

	# Generage report
	source ./report.sh

	# Manage build pool if needed
	if [ $CHANGED_HADOOPS != 0 ] || [ $CHANGED_UDA != 0 ]; then
	        echo -e "\n${GREEN}Managing build pool directory...${NONE}"
        	source ./manage.sh
	        echo -e "${GREEN}Done!${NONE}"
	fi

	# Sending report
	echo -e "\n${GREEN}Sending report...${NONE}"
	ssh -X $USER@$UBUNTU_SERVER 'bash -s' < `pwd`/mailer.sh "$MAIL_DETAILS_FILE" "$MAIL_MESSAGE_FILE"
	echo -e "${GREEN}Sent!${NONE}"

	# Remove temporary mailing files
	rm -rf $MAIL_DETAILS_FILE
	rm -rf $MAIL_MESSAGE_FILE

	# Remove temporary build target destination
	rm -rf ${BUILD_TARGET_DESTINATION}

	# Finished
	exit 0
fi
