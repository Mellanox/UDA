#!/bin/bash

echoPrefix=`eval $ECHO_PATTERN`
totalTests=0
succeededTests=0
export REPORT_TABLES_MAPPER=$REPORT_INPUT_DIR/analizeResults.txt
export REPORT_TOTAL_SUMMARY=$REPORT_INPUT_DIR/totalSummary.txt

source $REPORT_INPUT_DIR/reportExports.sh

echo "$echoPrefix: creating report-tables file at $REPORT_INPUT_DIR"
echo -e "" > $REPORT_TABLES_MAPPER
echo -e "" > $REPORT_TOTAL_SUMMARY

#for dir in `find $REPORT_INPUT_DIR -type d -name ${TEST_DIR_PREFIX}*${ATTEMPT_DIR_INFIX}*`;do
#	echo "$echoPrefix: checking if the test $dir passed"
#	bash -x $SCRIPTS_DIR/testStatusAnalyzer.sh $dir
#done

terasortResultsDir=$REPORT_INPUT_DIR/$TERASORT_JOBS_DIR_NAME
if [ -d $terasortResultsDir ];then
	echo "$echoPrefix: analizing terasort results"
	bash $SCRIPTS_DIR/terasortAnallizer.sh $terasortResultsDir
fi

<<COMM1
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
COMM1

export TESTLINK_TESTS_OUTCOME=$REPORT_INPUT_DIR/testLinkOutcome.txt
export TESTLINK_TESTS_ERRORS=$REPORT_INPUT_DIR/testLinkErrors.txt
echo -n "" > $TESTLINK_TESTS_OUTCOME
echo -n "" > $TESTLINK_TESTS_ERRORS


<<COMM2
for i in $FALLBACK_TESTS_IN_COVERAGE;do
	bash $SCRIPTS_DIR/fallbackAnallizer.sh "$i"
done

bash $SCRIPTS_DIR/memoryAllocationsAnallizer.sh "VUDA-19_terasort" "max"
bash $SCRIPTS_DIR/memoryAllocationsAnallizer.sh "VUDA-17_terasort" "mid"

for i in $SETUP_VALIDATION_TESTS_IN_COVERAGE;do
	bash $SCRIPTS_DIR/setupAnallizer.sh "$i"
done

for i in $SUPPORTED_COMPARE_FUNCTION_TEXT_IN_COVERAGE;do
	bash $SCRIPTS_DIR/jobStatusAnallizer.sh "$i" "exlWORDCOUNT_SUCCEED"
done

for i in $SUPPORTED_COMPARE_FUNCTION_LONG_WRITABLE_IN_COVERAGE;do
	bash $SCRIPTS_DIR/piAnallizer_new.sh "$i"
done
COMM2

echo "$echoPrefix: the analyzed tests are: $ALL_TESTS_NAMES"
for i in $ALL_TESTS_NAMES;do
	echo "$echoPrefix: current test: $i"
	bash $SCRIPTS_DIR/jobStatusAnallizer.sh $i
done

echo "#!/bin/sh
	export REPORT_TABLES_MAPPER='$REPORT_TABLES_MAPPER'
	export REPORT_TOTAL_SUMMARY='$REPORT_TOTAL_SUMMARY'
	export TESTLINK_TESTS_OUTCOME='$TESTLINK_TESTS_OUTCOME'
	export TESTLINK_TESTS_ERRORS='$TESTLINK_TESTS_ERRORS'
	export TOTAL_TESTS=$totalTests
	export SUCCEEDED_TESTS=$succeededTests
" > $SOURCES_DIR/analyzeEnvExports.sh
