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
				<table border='1' cellpadding='7' cellspacing='7' width='100%'>
					<tr bgcolor='$FILL_COLOR_1'>
						<th>Execution name</th>
						<th>Total dataset (Gb)</th>
					</tr>
					<tr>
						<td>$exec</td>
						<td>$tslDATA_SET</td>
					</tr>
					<tr bgcolor='$FILL_COLOR_2'>
						<th>Valid</th>
						<th>Cores</th>
						<th>Errors count</th>
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
		
		errors=`grep -r -e "ERROR" -e "FATAL" $testDir/slave* $testDir/master* | grep -c ""`
		
		if (($exlSORT_SUCCEED==1));then
			sortStatus=$SUCCESS_CODE
			succeededTests=$((succeededTests+1))
		else
			sortStatus=$FAILURE_CODE
		fi
		
		coresBGColor=$STANDARD_BGCOLOR
		coresFontColor=$STANDARD_FONT_COLOR
		if (( $exlCORES != 0 )); then
			coresBGColor=$FATAL_BGCOLOR
			coresFontColor=$FATAL_FONT_COLOR
		fi
		allTables="$allTables
					<tr>
						<td>$sortStatus</td>
						<td bgcolor=$coresBGColor><font color='$coresFontColor'>$exlCORES</font></td>
						<td>$errors</td>
						<td>$exlDURATION</td>
					</tr>"
	done
	allTables="$allTables
			</table>"
done

currentDate=`eval $CURRENT_DATE_PATTERN`

allTablesDir=$allJobsDir/${SORT_OUTCOME_TABLE_FILE_NAME}_${currentDate}
echo $allTables >> $allTablesDir
echo "$allTablesDir" >> $REPORT_TABLES_MAPPER

summaryDir=$allJobsDir/${SORT_SUMMARY_TABLE_FILE_NAME}_${currentDate}
echo "export smrTOTAL_TESTS=$totalTests; export smrSUCCEEDED_TESTS=$succeededTests" >> $summaryDir
echo "$summaryDir" >> $REPORT_TOTAL_SUMMARY
