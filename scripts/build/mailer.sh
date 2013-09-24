#!/bin/bash

## 11 August 2013
## =====================
## Report mailing Script
## =====================
## This script handles the report mailing after the build process is complete.

# Set mailing parameters
MAIL_DETAILS=$1
MAIL_MESSAGE=$2

subject=`cat $MAIL_DETAILS | sed -n '1 p' | sed 's/_/ /g'`
attachment=`cat $MAIL_DETAILS | sed -n '2 p'`
recipients=`cat $MAIL_DETAILS | sed -n '3 p'`

# Send report
echo "Sending build report to $recipients..."
mutt -e "set content_type=text/html" -a "${attachment}" -s "${subject}" -- ${recipients} < $MAIL_MESSAGE > /dev/null 2>&1
# Check for send failure
while [ $? != 0 ]; do
	mutt -e "set content_type=text/html" -a "${attachment}" -s "${subject}" -- ${recipients} < $MAIL_MESSAGE > /dev/null 2>&1
done
