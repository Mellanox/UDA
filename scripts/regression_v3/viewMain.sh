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
headLine=$HEADLINE
reportComment=$REPORT_COMMENT
hadoopVersion=$HADOOP_VERSION
rmpLine=$RPM_LINE
csvName=`basename $CSV_FILE`
resultsDir=`awk -v dir=$CURRENT_NFS_RESULTS_DIR 'BEGIN{gsub("/.autodirect/", "" , dir); print dir}'`

if (($COLLECT_FLAG == 1));then
	report=$CURRENT_NFS_RESULTS_DIR/${REPORT_NAME}.${REPORT_TYPE}
else
	dirName=`basename $REPORT_INPUT`
	report=$TMP_DIR/${dirName}.${REPORT_TYPE}
	headLine="statistics for $dirName (full directory is $REPORT_INPUT)"
fi

echo "$echoPrefix: generating the report frame"
echo "<html>
	<body> 
		<h2> $headLine </h2><br>" > "$report"

if (($COLLECT_FLAG == 1));then
echo "	<p><h2><font color=$FONT_COLOR_1>version: $hadoopVersion </font></h2></p>
		<p><h3><font><i> $reportComment </i></font></h3></p>
		<p><h3> $rmpLine </h3></p>
		<p><h4> Path to results: $CURRENT_NFS_RESULTS_DIR </h4></p>
		<br>
	" >> "$report"
fi
#<p><h4><a href=$WINDOES_DIR_PREFIX/$CURRENT_NFS_RESULTS_DIR/$csvName>Configuration File</a></h4></p>
echo "<p><h3><font color=$FONT_COLOR_2>Functionality tests passed $SUCCEEDED_TESTS out of $TOTAL_TESTS</font></h3></p>" >> "$report"

terasortResults=`cat $REPORT_TABLES_MAPPER | grep "/${TERASORT_JOBS_DIR_NAME}/" | sort`
sortResults=`cat $REPORT_TABLES_MAPPER | grep "/${SORT_JOBS_DIR_NAME}/" | sort`
wordcountResults=`cat $REPORT_TABLES_MAPPER | grep "/${WORDCOUNT_JOBS_DIR_NAME}/" | sort`
testDFSIOResults=`cat $REPORT_TABLES_MAPPER | grep "/${TEST_DFSIO_JOBS_DIR_NAME}/" | sort`
piResults=`cat $REPORT_TABLES_MAPPER | grep "/${PI_JOBS_DIR_NAME}/" | sort`

insertTableToReport $report "$sortResults" "Sort"
insertTableToReport $report "$wordcountResults" "Wordcount"
insertTableToReport $report "$testDFSIOResults" "TestDFSIO"
insertTableToReport $report "$piResults" "Pi"
insertTableToReport $report "$terasortResults" "Terasort"

echo "</body>
	</html>" >> "$report"
	
echo "
	#!/bin/sh
	export REPORT_MESSAGE='$report'
" > $TMP_DIR/viewExports.sh
