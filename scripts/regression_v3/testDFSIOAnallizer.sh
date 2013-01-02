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
						<th>Slaves count</th>
						<th>Number of files</th>
					</tr>
					<tr bgcolor='$FILL_COLOR_3'>
						<td>$exec</td>
						<td>$SLAVES_COUNT</td>
						<td>$NR_FILES</td>
					</tr>
					<tr bgcolor='$FILL_COLOR_2'>
						<th>Valid</th>
						<th>Test type</th>
						<th>Cores</th>
						<th>Errors count</th>
						<th>Job duration (hadoop measurements)</th>
						<th>Job duration (our measurements)</th>
						<th>Total MBytes processed</th>
						<th>Throughput mb/sec</th>
						<th>Average IO rate mb/sec</th>
						<th>IO rate std deviation</th>
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
		# declerine variable valid

		if (($NR_FILES == $exlNUM_OF_FILES));then
			#valid=$SUCCESS_CODE
			succeededTests=$((succeededTests+1))
		else
			valid=$FAILURE_CODE
		fi
		
		if [[ $exlTEST_TYPE == "read" ]];then
			lineColor=$FILL_COLOR_5
		else
			lineColor=$FILL_COLOR_4
		fi
		
		coresBGColor=$lineColor
		coresFontColor=$STANDARD_FONT_COLOR
		if (( $exlCORES != 0 )); then
			coresBGColor=$FATAL_BGCOLOR
			coresFontColor=$FATAL_FONT_COLOR
		fi
		
		troughput=`echo "scale=2; ${exlTHROUGHPUT}" | bc`
		averageIoRate=`echo "scale=2; ${exlAVERAGE_IO_RATE}" | bc`
		IoRateStdDev=`echo "scale=2; ${exlIO_RATE_STD_DEV}" | bc`
		
		allTables="$allTables
						<tr bgcolor='$lineColor'>
							<td>$valid</td>
							<td>$exlTEST_TYPE</td>
							<td bgcolor=$coresBGColor><font color='$coresFontColor'>$exlCORES</font></td>
							<td>$errors</td>
							<td>$exlTEST_EXEC_TIME</td>
							<td>$exlDURATION_WITH_FLUSH</td>
							<td>$exlTOTAL_MB_PROCESSED</td>
							<td>$troughput</td>
							<td>$averageIoRate</td>
							<td>$IoRateStdDev</td>
						</tr>"
	done
	allTables="$allTables
		</table>"
done

currentDate=`eval $CURRENT_DATE_PATTERN`

allTablesDir=$allJobsDir/${TEST_DFSIO_OUTCOME_TABLE_FILE_NAME}_${currentDate}
echo $allTables >> $allTablesDir
echo "$allTablesDir" >> $REPORT_TABLES_MAPPER

summaryDir=$allJobsDir/${TEST_DFSIO_SUMMARY_TABLE_FILE_NAME}_${currentDate}
echo "export smrTOTAL_TESTS=$totalTests; export smrSUCCEEDED_TESTS=$succeededTests" >> $summaryDir
echo "$summaryDir" >> $REPORT_TOTAL_SUMMARY
