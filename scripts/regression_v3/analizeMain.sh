#!/bin/bash

echoPrefix=$(basename $0)
totalTests=0
succeededTests=0
export REPORT_TABLES_MAPPER=$REPORT_INPUT_DIR/analizeResults.txt
export REPORT_TOTAL_SUMMARY=$REPORT_INPUT_DIR/totalSummary.txt

echo "$echoPrefix: creating report-tables file at $REPORT_INPUT_DIR"
echo -e "" > $REPORT_TABLES_MAPPER

terasortResultsDir=$REPORT_INPUT_DIR/$TERASORT_JOBS_DIR_NAME
if [ -d $terasortResultsDir ];then
	echo "$echoPrefix: analizing terasort results"
	bash $SCRIPTS_DIR/terasortAnallizer.sh $terasortResultsDir
fi

sortResultsDir=$REPORT_INPUT_DIR/$SORT_JOBS_DIR_NAME
if [ -d $sortResultsDir ];then
	echo "$echoPrefix: analizing sort results"
	bash $SCRIPTS_DIR/sortAnallizer.sh $sortResultsDir
fi

testDFSIOResultsDir=$REPORT_INPUT_DIR/$TEST_DFSIO_JOBS_DIR_NAME
if [ -d $testDFSIOResultsDir ];then
	echo "$echoPrefix: analizing testDFSIO results"
	bash $SCRIPTS_DIR/testDFSIOAnallizer.sh $testDFSIOResultsDir
fi

piResultsDir=$REPORT_INPUT_DIR/$PI_JOBS_DIR_NAME
if [ -d $piResultsDir ];then
	echo "$echoPrefix: analizing pi results"
	bash $SCRIPTS_DIR/piAnallizer.sh $piResultsDir
fi

wordcountResultsDir=$REPORT_INPUT_DIR/$WORDCOUNT_JOBS_DIR_NAME
if [ -d $wordcountResultsDir ];then
	echo "$echoPrefix: analizing wordcount results"
	bash $SCRIPTS_DIR/wordcountAnallizer.sh $wordcountResultsDir
fi

for i in `cat $REPORT_TOTAL_SUMMARY`;do
	source $i
	totalTests=$((totalTests+smrTOTAL_TESTS))
	succeededTests=$((succeededTests+smrSUCCEEDED_TESTS))
done

echo "#!/bin/sh
	export REPORT_TABLES_MAPPER='$REPORT_TABLES_MAPPER'
	export REPORT_TOTAL_SUMMARY='$REPORT_TOTAL_SUMMARY'
	export TOTAL_TESTS=$totalTests
	export SUCCEEDED_TESTS=$succeededTests
" > $TMP_DIR/analizeExports.sh
