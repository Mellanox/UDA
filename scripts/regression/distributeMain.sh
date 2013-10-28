#!/bin/bash
#REPORT_MAILING_LIST="shania,oriz"
echoPrefix=`eval $ECHO_PATTERN`
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
	echo "$echoPrefix: report directory is $REPORT_MESSAGE"
else
	message="echoPrefix: wrong type of message: `cat $REPORT_MESSAGE`"
	echo $message
fi

# special mail for compreassion  - NEED TO REWRITE APPROPRIATLY
if (( $CODE_COVE_FLAG==1 )) && [[ -z $SESSION_EXCEPTION ]];then 
	echo "$echoPrefix: covselect --file $CODE_COVERAGE_AGGREIGATED_COVFILE -i $CODE_COVERAGE_EXCLUDE_PATH"
	covselect --file $CODE_COVERAGE_AGGREIGATED_COVFILE -i $CODE_COVERAGE_EXCLUDE_PATH
	echo "$echoPrefix: eval $CODE_COVERAGE_COMMIT_SCRIPT_PATH --branch $GIT_BRANCH --product $PRODUCT_NAME --team $TEAM_NAME --version $VERSION_SHORT_FORMAT --path $CODE_COVERAGE_COMMIT_DIR"
	if [[ -z $BULLSEYE_DRYRUN ]];then
		eval $CODE_COVERAGE_COMMIT_SCRIPT_PATH --branch $GIT_BRANCH --product $PRODUCT_NAME --team $TEAM_NAME --version $VERSION_SHORT_FORMAT --path $CODE_COVERAGE_COMMIT_DIR 
	else
		echo "$echoPrefix: dry-run mode - the coverage-report won't be sent"
	fi
fi

echo "$echoPrefix: sending mail to $recipientList" | tee $STATUS_DIR/mailRecipient.txt
python $SCRIPTS_DIR/mailSender.py "$subject" "$message" "`date`" "$USER" "$recipientList"

echo "
	#!/bin/sh
" > $SOURCES_DIR/distributeExports.sh
