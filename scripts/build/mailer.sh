#!/bin/bash
#MAILING_LIST="shania,oriz"
mailingScript=$1
mailingList=$2
allContacts=`echo $mailingList | awk 'BEGIN {RS=",";}{print  $1}'`;

count=0
for i in $allContacts;do
	count=$((count+1))
done
iterator=0
recipientList=""
for i in $allContacts
do
	iterator=$((iterator+1))
	recipientList="${recipientList}${i}@mellanox.com"
	if (($iterator == $count));then
		break;
	fi
	recipientList="${recipientList}, "
done

subject=$REPORT_SUBJECT
#messageType=`echo $REPORT_MESSAGE | grep -c "<html>"`
#if (($messageType==1));then
#	message=$REPORT_MESSAGE
#elif (($messageType==0));then
#	message=`cat $REPORT_MESSAGE`
#	echo "echoPrefix: report directory: $REPORT_MESSAGE"
#else
#	message="echoPrefix: wrong type of message: `cat $REPORT_MESSAGE`"
#	echo $message
#fi
#
echo "Sending build report to $recipientList..."
python $mailingScript "$subject" "hey" "`date`" "$USER" "$recipientList"
