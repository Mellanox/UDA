#!/bin/bash

## 11 August 2013
## =====================
## Report mailing Script
## =====================
## This script handles the report mailing after the build process is complete.

# Set mailing parameters
MAIL_DETAILS=$1

subject=`cat $MAIL_DETAILS | sed -n '1 p'`
message=`cat $MAIL_DETAILS | sed -n '2 p'`
attachment=`cat $MAIL_DETAILS | sed -n '3 p'`
recipients=`cat $MAIL_DETAILS | sed -n '4 p'`

# Create message file
echo "${message}" > message.html

# Send report
echo "Sending build report to $recipients..."
mutt -e "set content_type=text/html" -a "${attachment}" -s "${subject}" -- ${recipients} < message.html > /dev/null 2>&1
# Check for send failure
while [ $? != 0 ]; do
	mutt -e "set content_type=text/html" -a "${attachment}" -s "${subject}" -- ${recipients} < message.html > /dev/null 2>&1
done

# Remove message file
rm -f message.html
