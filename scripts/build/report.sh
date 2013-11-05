#!/bin/bash

## 11 August 2013
## ========================
## UDA Hadoop Report Script
## ========================
## This script generated the report sent at the end of the build process.

# Edit mailing message
echo -e "\n${YELLOW}Generating report...${NONE}"

# Title
MAIL_MESSAGE="<h1>UDA|HADOOP Daily Build Report</h1><br>"

# Target
MAIL_MESSAGE=${MAIL_MESSAGE}"The built products can be found in <b>"${BUILD_POOL}"</b><br>"
MAIL_MESSAGE=${MAIL_MESSAGE}"To access the built products through Windows go to <b>"${BUILD_POOL_WINDOWS}"</b><br><br>"

# Calculate changes made
let "NUM_OF_CHANGED_HADOOPS = `wc -l ${DB_DIR}/changes_hadoops | cut -d " " -f 1`"
let "NUM_OF_CHANGED_UDA = `wc -l ${DB_DIR}/changes_uda | cut -d " " -f 1`"
export CHANGED_HADOOPS=$NUM_OF_CHANGED_HADOOPS
export CHANGED_UDA=$NUM_OF_CHANGED_UDA

# Update mail message according to changes
if ([ $CHANGED_HADOOPS == 0 ] && [ $CHANGED_UDA == 0 ]) || ([ $CHANGED_HADOOPS != 0 ] && [ $BUILD_HADOOPS == "FALSE" ] && [ $CHANGED_UDA == 0 ]) || ([ $CHANGED_HADOOPS == 0 ] && [ $CHANGED_UDA != 0 ] && [ $BUILD_RPM == "FALSE" ]); then
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
		echo -e "${PURPLE}Including commit history since ${latest_uda_date}...${NONE}"
		MAIL_MESSAGE=${MAIL_MESSAGE}"The lastest commits in UDA git:<br><ul>"
		cd ${TMP_CLONE_DIR}/${UDA_BRANCH_DIR}			
		MAIL_MESSAGE=${MAIL_MESSAGE}`git log --pretty=format:"<li>%an%x09%ad%x09%s</li>" --after={${latest_uda_date}}`
		MAIL_MESSAGE=${MAIL_MESSAGE}"</ul><br>"
		cd ${BUILD_DIR}
	fi
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

echo -e "${YELLOW}Report Generated!${NONE}"
