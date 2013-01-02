#!/bin/bash

echoPrefix=`eval $ECHO_PATTERN`
allJobsDir=$1
totalTests=0
succeededTests=0
allTables=""

for exec in `ls $allJobsDir | grep $EXEC_DIR_PREFIX`
do
	execDir=$allJobsDir/$exec
	if [ -f $execDir ];then # skip if its not a folder
	continue
	fi
	source $execDir/testLogExports.sh
	allTables="$allTables
				<table $PI_TABLE_ATTR>
					<tr bgcolor='$FILL_COLOR_1'>
						<th>Execution name</th>
						<th>Pi-mappers</th>
						<th>Pi-samples</th>
					</tr>
					<tr>
						<td>$exec</td>
						<td>$PI_MAPPERS</td>
						<td>$PI_SAMPLES</td>
					</tr>
					<tr bgcolor='$FILL_COLOR_2'>
						<th>Valid</th>
						<th>Cores</th>
						<th>Errors count</th>
						<th>pi estimation</th>
						<th>Job duration</th>
					</tr>"
	
	for test  in `ls $execDir | grep $TEST_DIR_PREFIX`
	do
		testDir=$execDir/$test
		if [ -f $testDir ];then
			continue
		fi
		source $testDir/execLogExports.sh
		totalTests=$((totalTests+1))
		
		piDelta=`echo "scale=4; ${PI_REAL_VALUE}-${exlPI_ESTIMATION}" | bc`
		piDelta=`echo "scale=4; sqrt(${piDelta}^2)" | bc` # avoiding negative numbers
		errorRate=`echo "${piDelta}>${PI_NUMERIC_ERROR}" | bc`
		if (($errorRate==0));then
			valid=$SUCCESS_CODE
			succeededTests=$((succeededTests+1))
		else
			valid=$FAILURE_CODE
		fi
		
		errors=`grep -r -e "ERROR" -e "FATAL" $testDir/slave* $testDir/master* | grep -c ""`
		
		coresBGColor=$STANDARD_BGCOLOR
		coresFontColor=$STANDARD_FONT_COLOR
		if (( $exlCORES != 0 )); then
			coresBGColor=$FATAL_BGCOLOR
			coresFontColor=$FATAL_FONT_COLOR
		fi
					
		allTables="$allTables
						<tr>
							<td>$valid</td>
							<td bgcolor=$coresBGColor><font color='$coresFontColor'>$exlCORES</font></td>
							<td>$errors</td>							
							<td>$exlPI_ESTIMATION</td>
							<td>$exlDURATION_WITH_FLUSH</td>
						</tr>"
	done
	allTables="$allTables
				</table>"
done

currentDate=`eval $CURRENT_DATE_PATTERN`

allTablesDir=$allJobsDir/${PI_OUTCOME_TABLE_FILE_NAME}_${currentDate}
echo $allTables >> $allTablesDir
echo "$allTablesDir" >> $REPORT_TABLES_MAPPER

summaryDir=$allJobsDir/${PI_SUMMARY_TABLE_FILE_NAME}_${currentDate}
echo "export smrTOTAL_TESTS=$totalTests; export smrSUCCEEDED_TESTS=$succeededTests" >> $summaryDir
echo "$summaryDir" >> $REPORT_TOTAL_SUMMARY

