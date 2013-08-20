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
	latest_uda_date=`cat ${DB_DIR}/latest_uda | cut -d " " -f 1`

        # Build and log
	source ./build.sh | tee "${LOG_DIR}/${LOG}"

	# Edit mailing message
	# Title
	MAIL_MESSAGE="<h1>UDA Daily Build Report</h1><br>"
	# Target
	MAIL_MESSAGE=${MAIL_MESSAGE}"The built products can be found in <b>"${BUILD_POOL}"</b><br>"
	MAIL_MESSAGE=${MAIL_MESSAGE}"To access the built products through Windows go to <b>"${BUILD_POOL_WINDOWS}"</b><br><br>"
	# Calculate changes made
	let "NUM_OF_CHANGED_HADOOPS = `wc -l ${DB_DIR}/changes_hadoops | cut -d " " -f 1`"
	let "NUM_OF_CHANGED_UDA = `wc -l ${DB_DIR}/changes_uda | cut -d " " -f 1`"
	export CHANGED_HADOOPS=$NUM_OF_CHANGED_HADOOPS
	export CHANGED_UDA=$NUM_OF_CHANGED_UDA
	# Update mail message according to changes
	if [ $CHANGED_HADOOPS == 0 ] && [ $CHANGED_UDA == 0 ]; then
		MAIL_MESSAGE=${MAIL_MESSAGE}"No changes made since last build.<br> Nothing new was built.<br>"
	else
		# Products
		MAIL_MESSAGE=${MAIL_MESSAGE}"The daily built products were:<br><ul>"
		for product in `ls -p ${BUILD_TARGET_DESTINATION} | grep -v "/"`; do
			MAIL_MESSAGE=${MAIL_MESSAGE}"<li>"$product"</li>"
		done
		MAIL_MESSAGE=${MAIL_MESSAGE}"</ul><br>"
		# Commit History
		if [ $CHANGED_UDA != 0 ]; then
			MAIL_MESSAGE=${MAIL_MESSAGE}"The lastest commits in UDA git:<br><ul>"
			cd ${TMP_CLONE_DIR}/${UDA_BRANCH_DIR}			
			MAIL_MESSAGE=${MAIL_MESSAGE}`git log --pretty=format:"<li>%an%x09%ad%x09%s</li>" --after={${latest_uda_date}}`
			MAIL_MESSAGE=${MAIL_MESSAGE}"</ul><br>"
			cd ${BUILD_DIR}
		fi

		# Manage build pool
		echo -e "\n${GREEN}Managing build pool directory...${NONE}"
		source ./manage.sh
		echo -e "${GREEN}Done!${NONE}"
	fi

	# Mail message HTML Warpper
	MAIL_MESSAGE="<html><body><font face=""Calibri"" size=3>"${MAIL_MESSAGE}"</font></body></html>"
	# Set mailing parameters
	MAIL_ATTACHMENT=${LOG_DIR}/${LOG_FILE}
	for recipient in `echo ${MAILING_LIST} | sed 's/,/ /g'`; do
		MAIL_RECIPIENTS="${recipient}@mellanox.com ${MAIL_RECIPIENTS}"
	done
	MAIL_DETAILS_FILE=`pwd`/mail_details
	MAIL_MESSAGE_FILE=`pwd`/mail_message
	echo "${MAIL_SUBJECT}" >> $MAIL_DETAILS_FILE
	echo "${MAIL_ATTACHMENT}" >> $MAIL_DETAILS_FILE
	echo "${MAIL_RECIPIENTS}" >> $MAIL_DETAILS_FILE
	echo "${MAIL_MESSAGE}" >> $MAIL_MESSAGE_FILE

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
