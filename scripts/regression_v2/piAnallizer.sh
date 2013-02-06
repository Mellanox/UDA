#!/bin/bash

echoPrefix=$(basename $0)
allTables=""

echo "$echoPrefix: outcomming the pi tests"

allJobsDir=$PI_RESULTS_INPUT_DIR
piOutcomeTable="<table border='1' cellpadding='7' cellspacing='7' width='100%'>
				<tr>
					<td><b>Execution name</b></td>
					<td><b>Pi-mappers</b></td>
					<td><b>Pi-samples</b></td>
					<td><b>Errors count</b></td>
					<td><b>pi estimation</b></td>
					<td><b>Valid</b></td>
				</tr>
			"
for exec in `ls $allJobsDir | grep $EXEC_DIR_PREFIX`
do
	execDir=$allJobsDir/$exec
	if [ -f $execDir ];then # skip if its not a folder
	continue
	fi
	source $execDir/testLogExports.sh
	for test  in `ls $execDir | grep $TEST_DIR_PREFIX`
	do
		testDir=$execDir/$test
		if [ -f $testDir ];then
			continue
		fi
		source $testDir/execLogExports.sh
		
		errors=`grep -r "ERROR" $testDir/slave* | grep -c ""`
		errors=$((errors+`grep -r "ERROR" $testDir/master* | grep -c ""`))
		wrongOutput=`grep -r "PI estimation FAILED" $testDir/log.txt | grep -c ""`
		if (($wrongOutput==1));then
			estimationStatus=$FAILURE_CODE
		else
			estimationStatus=$SUCCESS_CODE
		fi
		piOutcomeTable="$piOutcomeTable
						<tr>
							<td>$exec</td>
							<td>$PI_MAPPERS</td>
							<td>$PI_SAMPLES</td>
							<td>$errors</td>
							<td>$exlPI_ESTIMATION</td>
							<td>$estimationStatus</td>
						</tr>"
	done
done
piOutcomeTable="$piOutcomeTable </table>"
currentDate=`date +"%Y-%m-%d_%H.%M.%S"`
piOutcomeTableDir=$PI_RESULTS_INPUT_DIR/${REP_PI_OUTCOME_TABLE_FILE_NAME}_${currentDate}
echo $piOutcomeTable >> $piOutcomeTableDir
echo "$piOutcomeTableDir" >> $REPORT_INPUT_DIR/analizeResults.txt
