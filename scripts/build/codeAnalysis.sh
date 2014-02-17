#!/bin/bash

## 10 December 2013
## ====================
## Static code analysis
## ====================
## This script runs Coverity on UDA to check for bugs in the C code.
## This script e-mails a static code analysis report.


# Configuring Running Directory
RUNNING_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $RUNNING_DIR

# Configure report files
REPORTS_STORAGE="/.autodirect/acclgwork/uda/static_code_analysis/"
C_REPORT_FILE="c_analysis_report.html"

###################
# C Code Analysis #
###################

echo -e "\n******************* Static code analysis in progress... *******************"

# Move back to running directory
cd $RUNNING_DIR

# Move to the C code src folder
cd ../../src/

# Run PreMake
echo -e "\n${CYAN}---------- Step 1. Running PreMake... ----------${NONE}"
./premake.sh  > /dev/null 2>&1
echo -e "\n${GREEN}Step 1 Done!${NONE}"

# Move to the C code src folder
cd $RUNNING_DIR/../../src/

# Run Covertiy
echo -e "\n${CYAN}---------- Step 2. Running Coverity... ----------${NONE}"
make cov > $RUNNING_DIR/$C_REPORT_FILE
if [ $? != 0 ]; then
	echo -e "\n[ERROR] Error while running coverity!"
	exit 1
fi
echo -e "\n${GREEN}Step 2 Done!${NONE}"

# Config Report
cp cov-build/c/output/errors/index.html ${RUNNING_DIR}/${C_REPORT_FILE}

# Calculate number of errors
let "C_ERRORS = `grep "error" ${RUNNING_DIR}/${C_REPORT_FILE} | wc -l`"

#################
# Store Reports #
#################

echo -e "\n${CYAN}---------- Step 3. Storing report... ----------${NONE}"

# Move back to running directory
cd $RUNNING_DIR

# Storing
folder=`date +"%Y_%m_%d"`
mkdir -p ${REPORTS_STORAGE}/${folder}

# Store C report
toreplace="1\/"
replacewith="\\\\\\\\mtrlabfs01\\\\acclgwork\\\\uda\\\\static_code_analysis\\\\$folder\\\\src\\\\cov-build\\\\c\\\\output\\\\errors\\\\1\\\\"
sed -i "s/$toreplace/$replacewith/g" ${C_REPORT_FILE}

cp ${C_REPORT_FILE} ${REPORTS_STORAGE}/${folder}
cp -r ../../src/ ${REPORTS_STORAGE}/${folder}

echo -e "\n${GREEN}Step 3 Done!${NONE}"

################
# Send Reports #
################

echo -e "\n${CYAN}---------- Step 4. Sending report... ----------${NONE}"

# Move back to running directory
cd $RUNNING_DIR

# Define report parameters
attachment="$C_REPORT_FILE"
subject="UDA Code Analysis Report"
if ([ $C_ERRORS == 0 ]); then
	subject="${subject} - no issues found"
else
	subject="${subject} - found $C_ERRORS issue(s)"
fi
for recipient in `echo ${CODE_ANALYSIS_MAILING_LIST} | sed 's/,/ /g'`; do
        MAIL_RECIPIENTS="${recipient}@mellanox.com ${MAIL_RECIPIENTS}"
done
MAIL_MESSAGE=mail.html
MAIL_MESSAGE_HTML="<h1>UDA Code Analysis Report</h1><br>Attached is the UDA C code analysis for `date +%d/%m/%y`.<br><br>"
if [ $C_ERRORS != 0 ]; then
	MAIL_MESSAGE_HTML="${MAIL_MESSAGE_HTML} Found $C_ERRORS C Errors/Warnings.<br>"
fi

# Configure report
MAIL_MESSAGE_HTML="<html><body><font face=""Calibri"" size=3>"${MAIL_MESSAGE_HTML}"</font></body></html>"
echo $MAIL_MESSAGE_HTML > $MAIL_MESSAGE

# Send report
mutt -e "set content_type=text/html" -a $attachment -s "${subject}" -- ${MAIL_RECIPIENTS} < $MAIL_MESSAGE > /dev/null 2>&1
while [ $? != 0 ]; do
        mutt -e "set content_type=text/html" -a $attachment -s "${subject}" -- ${MAIL_RECIPIENTS} < $MAIL_MESSAGE > /dev/null 2>&1
done
echo -e "${GREEN}Sent!${NONE}"

echo -e "\n${GREEN}Step 4 Done!${NONE}"

echo -e "\n${GREEN}Finished running static code analysis.${NONE}"

# Cleaning Up
rm -f $C_REPORT_FILE
rm -rf $MAIL_MESSAGE
