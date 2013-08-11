#!/bin/bash

echoPrefix=`eval $ECHO_PATTERN`
headLine=$HEADLINE
reportComment=$REPORT_COMMENT
rpmLine="RPM: $INSTALLED_RPM"
csvName=`basename $CSV_FILE`
resultsDir=`awk -v dir=$CURRENT_NFS_RESULTS_DIR 'BEGIN{gsub("/.autodirect/", "" , dir); print dir}'`

if (($COLLECT_FLAG == 1));then
	report=$CURRENT_NFS_RESULTS_DIR/${REPORT_NAME}.${REPORT_TYPE}
else
	dirName=`basename $REPORT_INPUT`
	report=$TMP_DIR/${dirName}.${REPORT_TYPE}.${CURRENT_DATE}
	headLine="statistics for $dirName (full directory is $REPORT_INPUT)"
fi

echo "$echoPrefix: generating the report frame"
echo "<html>
	<body> 
		<h2> $headLine </h2><br>" >> "$report"

if (($CODE_COVE_FLAG==1));then
	covTotal=`cat $CODE_COVERAGE_SUMMARY | tail -1 | awk 'BEGIN {funcs=6; blocks=11}{print "functions:", $funcs, "blocks:", $blocks}'`
	echo "<p><h1>RUNNING WITH BULLSEYE</h1></p>
		<p><h2> $covTotal </h2></p>
		<p><h3>full report directory: $CODE_COVERAGE_SUMMARY </h3></p>" >> "$report"
fi
		
if (($COLLECT_FLAG == 1));then
echo "	<p><h3><font><i> $reportComment </i></font></h3></p>
		<p><h3> $rpmLine </h3></p>
		<p><h4> Path to results: $CURRENT_NFS_RESULTS_DIR </h4></p>
		<br>
	" >> "$report"
fi
#<p><h4><a href=$WINDOES_DIR_PREFIX/$CURRENT_NFS_RESULTS_DIR/$csvName>Configuration File</a></h4></p>
#echo "<p><h3><font color=$FONT_COLOR_2>Functionality tests passed $SUCCEEDED_TESTS out of $TOTAL_TESTS</font></h3></p>" >> "$report"

for inter in $ENV_REPORT_DIRS;do
	cat $inter >> "$report"
done

echo "</body>
	</html>" >> "$report"
	
echo "
	#!/bin/sh
	export REPORT_MESSAGE='$report'
" > $SOURCES_DIR/viewExports.sh

