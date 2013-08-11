#!/bin/bash

insertTableToReport()
{
	if [[ -n $2 ]];then
		echo "<h2>$3</h2>" >> "$1"
		for line in $2;do
			echo "$echoPrefix: inserting table $line"
			eval cat $line >> "$1"
		done
	fi
	
	echo "<br><br>" >> "$1"
}

echoPrefix=`eval $ECHO_PATTERN`
hadoopVersion=$HADOOP_VERSION

envReport=$CURRENT_NFS_ENV_RESULTS_DIR/${REPORT_INTERMEDIATE_NAME}
#<!-- 
#-->
echo "	<p><h2><font color=$FONT_COLOR_1>$ENV_NAME</font></h2></p>
		<p><h3><font>version: $hadoopVersion</font></h3></p>
		<br>
	" >> "$envReport"

terasortResults=`cat $REPORT_TABLES_MAPPER | grep "/${TERASORT_JOBS_DIR_NAME}/" | sort`
sortResults=`cat $REPORT_TABLES_MAPPER | grep "/${SORT_JOBS_DIR_NAME}/" | sort`
wordcountResults=`cat $REPORT_TABLES_MAPPER | grep "/${WORDCOUNT_JOBS_DIR_NAME}/" | sort`
testDFSIOResults=`cat $REPORT_TABLES_MAPPER | grep "/${TEST_DFSIO_JOBS_DIR_NAME}/" | sort`
piResults=`cat $REPORT_TABLES_MAPPER | grep "/${PI_JOBS_DIR_NAME}/" | sort`

awk -v tableProperties="border='1' cellpadding='1' cellspacing='1'" -v successColor=$STANDARD_BGCOLOR -v failureColor=$ERROR_BGCOLOR -f $SCRIPTS_DIR/testLinkReportBuilder.awk $TESTLINK_TESTS_OUTCOME >> "$envReport"

if [[ -n $TESTLINK_TESTS_ERRORS ]];then
	echo "<br><br><p><h3>Errors:</h3></p>
		<p>"`cat $TESTLINK_TESTS_ERRORS`"</p>" >> "$envReport"
fi

insertTableToReport $envReport "$terasortResults" "Terasort"
#insertTableToReport $envReport "$sortResults" "Sort"
#insertTableToReport $envReport "$wordcountResults" "Wordcount"
#insertTableToReport $envReport "$testDFSIOResults" "TestDFSIO"
#insertTableToReport $envReport "$piResults" "Pi"
	
echo "
	#!/bin/sh
	export ENV_REPORT_DIRS='$ENV_REPORT_DIRS $envReport'
" > $SOURCES_DIR/viewEnvExports.sh

