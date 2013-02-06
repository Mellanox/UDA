#!/bin/bash

echoPrefix=$(basename $0)
blankLines="<br><br>"
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
	headLine="statistics for $dirName"
fi

echo "$echoPrefix: generating the report frame"
echo "<html>
	<body> 
		<h2> $headLine </h2><br>
	" > "$report"

if (($COLLECT_FLAG == 1));then
echo "	<h2><font color='DodgerBlue'>version: $hadoopVersion </font></h2> 
		<p><h3><font><i> $reportComment </i></font></h3></p>
		<p><h3> $rmpLine </h3></p>
		<p><h4> Path to results: $CURRENT_NFS_RESULTS_DIR </h4></p>
		<p><h4><a href=$WINDOES_DIR_PREFIX/$CURRENT_NFS_RESULTS_DIR/$csvName>Configuration File</a></h4></p>
	" >> "$report"
fi

terasortResults=`cat $REPORT_INPUT_DIR/analizeResults.txt | grep $TERASORT_JOBS_DIR_NAME | sort`
#testDFSIOResults=`cat $REPORT_INPUT_DIR/analizeResults.txt | grep $TEST_DFSIO_JOBS_DIR_NAME`
piResults=`cat $REPORT_INPUT_DIR/analizeResults.txt | grep $PI_JOBS_DIR_NAME | sort`
for line in $terasortResults
do
	echo "$echoPrefix: inserting table $line"
	eval cat $line >> "$report"
done

echo $blankLines >> "$report"

for line in $piResults
do
	echo "$echoPrefix: inserting table $line"
	eval cat $line >> "$report"
done

<<C
for exec in `ls $allJobsDir | grep $EXEC_DIR_PREFIX`
do
	execDir=$allJobsDir/$exec
	if [ -f $execDir ];then # skip if its not a folder
		continue
	fi
	
	for sample  in `ls $execDir | grep $SAMPLE_DIR_INFIX`
	do
		sampleDir=$execDir/$sample
		if [ -f $sampleDir ];then
			continue
		fi
		
		for test  in `ls $sampleDir | grep $TEST_DIR_PREFIX`
		do
			testDir=$sampleDir/$test
			if [ -f $testDir ];then
				continue
			fi
			
			table=`find . -name $REP_TERASORT_DATA_TABLE_FILE_NAME`
		done #test
		
	done #sample	
done #exec
C

echo "
	#!/bin/sh
	
	export REPORT_MESSAGE='$report'
" > $TMP_DIR/viewExports.sh
