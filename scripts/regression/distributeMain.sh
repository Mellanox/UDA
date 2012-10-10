#!/bin/bash
REPORT_MAILING_LIST="shania,oriz"
echoPrefix=$(basename $0)
allContacts=`echo $REPORT_MAILING_LIST | awk 'BEGIN {RS=",";}{print  $1}'`;

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

echo "$echoPrefix: sending mail to $recipientList"
python $SCRIPTS_DIR/mailSender.py "$subject" "$message" "`date`" "$USER" "$recipientList"

echo "
	#!/bin/sh
" > $TMP_DIR/distributeExports.sh
