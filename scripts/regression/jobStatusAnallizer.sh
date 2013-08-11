#!/bin/sh

echoPrefix=`eval $ECHO_PATTERN`

testName=$1
#successCriteria=$2
totalTests=0
succeededTests=0

for exec in `find $REPORT_INPUT_DIR -type d -name ${EXEC_DIR_PREFIX}\*${testName}`
do
	source $exec/testLogExports.sh
	echo "$echoPrefix: analyzing $exec"
	for test in `ls $exec | grep $TEST_DIR_PREFIX`
	do
		echo "$echoPrefix: current test: $test"
		testDir=$exec/$test
		if [ -f $testDir ];then # skip if its not a folder
			continue
		fi
		source $testDir/execLogExports.sh
		
		#if (($PERFORNAMCE_TEST==1));then
		#	continue
		#fi
		
		totalTests=$((totalTests+1)) 
		
		#eval successCriteriaValue=\$$successCriteria # getting the value of the variable with "inside" successCriteria
		if (($TEST_STATUS == 1));then
			succeededTests=$((succeededTests+1))
		else
			echo -n "Test name: ${testName}.   " >> $TESTLINK_TESTS_ERRORS
			if [ -n "$TEST_ERROR" ];then
				echo "description: ${TEST_ERROR}.   " >> $TESTLINK_TESTS_ERRORS
			fi
			echo "directory: ${testDir}" >> $TESTLINK_TESTS_ERRORS
		fi
	done
	
done

if (($totalTests != 0));then
	echo "$testName $succeededTests $totalTests" >> $TESTLINK_TESTS_OUTCOME
fi