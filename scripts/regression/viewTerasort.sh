#!/bin/bash

echoPrefix=$(basename $0)

standardBGColor="White"
successBGColor="GreenYellow"
warnBGColor="Gold"
errorBGColor="Crimson"
fatalBGColor="Maroon"
standardFontColor="Black"
successFontColor="Black"
warnFontColor="Black"
errorFontColor="Black"
fatalFontColor="White"
successCode="&#10003"
failureCode="&#10007"
errorColor="Crimson"

headLine=$HEADLINE
reportComment=$REPORT_COMMENT
hadoopVersion=$HADOOP_VERSION
rmpLine=$RPM_LINE
csvName=`basename $CSV_FILE`
resultsDir=`awk -v dir=$CURRENT_NFS_RESULTS_DIR 'BEGIN{gsub("/.autodirect/", "" , dir); print dir}'`
echo  resultsDir: $resultsDir

if (($COLLECT_FLAG == 1));then
	report=$CURRENT_NFS_RESULTS_DIR/regression.html
else
	dirName=`basename $REPORT_INPUT`
	report=$TMP_DIR/${dirName}.html
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

echo "
	#!/bin/sh
	export STANDARD_BGCOLOR='$standardBGColor'
	export STANDARD_FONT_COLOR='$standardFontColor'
	export SUCCEEDED_BGCOLOR='$successBGColor'
	export PASSED_BGCOLOR='$warnBGColor'
	export FATAL_BGCOLOR='$errorBGColor'
	export FAILED_BGCOLOR='$fatalBGColor'
	export SUCCEEDED_FONT_COLOR='$successFontColor'
	export PASSED_FONT_COLOR='$warnFontColor'
	export FATAL_FONT_COLOR='$errorFontColor'
	export FAILED_FONT_COLOR='$fatalFontColor'	
	export SUCCESS_CODE='$successCode'
	export FAILURE_CODE='$failureCode'
	export REPORT_MESSAGE='$report'
	#export ERROR_COLOR='$errorColor'
" > $TMP_DIR/viewExports.sh
