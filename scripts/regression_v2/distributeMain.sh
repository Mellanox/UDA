#!/bin/bash
#REPORT_MAILING_LIST="shania,oriz"
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


if (( $CODE_COVE_FLAG==1 ))
then 
 
echo "covselect -f $COVERAGE_DEST_DIR/total_cov.cov -i /tmp/exclude"
covselect -f $COVERAGE_DEST_DIR/total_cov.cov -i /tmp/exclude
covTotal=`covdir -f $COVERAGE_DEST_DIR/total_cov.cov | tail -1 | awk 'BEGIN {FS=" "}; {a = $6} {b= $11}{print "function:", a, "blocks:", b}'`
covMessage="<html> <body> <p><h1>RUNNING WITH BULLSEYE!!<h1\><p\> <p><h2> $covTotal <h2\><p\> <p> <h3>You can find the full report here: $COVERAGE_DEST_DIR/total_cov.cov <h3\><p\> <body\> <html\>"
echo "/.autodirect/mswg/utils/bin/coverage/commit_cov_files.sh -B master -P UDA -V 3.0 -T UDA -p $COVERAGE_DEST_DIR"
/.autodirect/mswg/utils/bin/coverage/commit_cov_files.sh -B master -P UDA -V 3.0 -T UDA -p $COVERAGE_DEST_DIR 
message="${covMessage} ${message} "

fi

echo "$echoPrefix: sending mail to $recipientList" | tee  $STATUS_DIR/mailRecipient.txt
python $SCRIPTS_DIR/mailSender.py "$subject" "$message" "`date`" "$USER" "$recipientList"


echo "
	#!/bin/sh
" > $TMP_DIR/distributeExports.sh
