#!/bin/bash

echoPrefix=$(basename $0)
allContacts=`echo $REPORT_MAILING_LIST | awk 'BEGIN {RS=",";}{print $1}'`;
allContacts="oriz"
subject=$REPORT_SUBJECT
messageType=`echo $REPORT_MESSAGE | grep -c "<html>"`
if (($messageType==1));then
	message=$REPORT_MESSAGE
elif (($messageType==0));then
	message=`cat $REPORT_MESSAGE`
	echo "echoPrefix: report directory: $REPORT_MESSAGE"
else
	message="echoPrefix: wrong type of message: `cat $REPORT_MESSAGE`"
	echo $message
fi

for content in $allContacts
do  
	echo "$echoPrefix: sending mail to $content"
	python $SCRIPTS_DIR/mailSender.py "$subject" "$message" "`date`" "$USER" "$content"
done 

echo "
	#!/bin/sh
" > $TMP_DIR/distributeExports.sh
