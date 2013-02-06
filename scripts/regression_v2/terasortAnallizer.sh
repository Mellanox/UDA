#!/bin/bash

getTime (){
	local TL=`echo $@ | awk 'BEGIN{FS="("} {print $2}'`
	local dummy=$TMP_DIR/csvDummy.csv
	echo "," > $dummy
	getTimeRetVal=`awk -v timeLine="$TL" -f $SCRIPTS_DIR/getTime.awk $dummy` # the CSV_FILE is here just because awk scripts must have input file
}

stdDev (){ 
	local count=$1
	local average=$2
	shift
	shift
	local stdDev=0
	for i in `seq 1 $count`;do
		local arrMember=$1
		shift
		local distFromTheExp=`echo "scale=2; ${arrMember}-${average}" | bc`
		stdDev=`echo "scale=2; ${stdDev}+${distFromTheExp}^2" | bc`
	done
	getStdDev=`echo "scale=2; sqrt($stdDev/$count)" | bc`
}

findMinDuration()
{
	local min=$1
	for i in $@;do
		if (($min > $i));then
			min=$i
		fi
	done
	if (($min == $minDuration));then
		getMinDuration=$maxDuration # = 0 (in general code-writing)
	else
		getMinDuration=$min
	fi
}

findMaxDuration()
{
	local max=$1
	for i in $@;do
		if (($max < $i));then
			max=$i
		fi
	done
	getMaxDuration=$max
}

echoPrefix=$(basename $0)
allTables=""

echo "$echoPrefix: making statistics for $TERASORT_RESULTS_INPUT_DIR"

allJobsDir=$TERASORT_RESULTS_INPUT_DIR

for exec in `ls $allJobsDir | grep $EXEC_DIR_PREFIX`
do
	execDir=$allJobsDir/$exec
	if [ -f $execDir ];then # skip if its not a folder
		continue
	fi
	
	testNum=0
	status=0
	jobStatus=0
	jobDuration=0
	successDuration=0
	successCount=0
	warnDuration=0
	warnCount=0
	errorDuration=0
	errorCount=0
	fatalDuration=0
	fatalCount=0
	maxDuration=0
	minDuration=1000000000000000 # just some very big number
	successMaxDuration=$maxDuration
	successMinDuration=$minDuration
	warnMaxDuration=$maxDuration
	warnMinDuration=$minDuration
	errorMaxDuration=$maxDuration
	errorMinDuration=$minDuration
	fatalMaxDuration=$maxDuration
	fatalMinDuration=$minDuration
	testsValues=""
	statisticsValues=""
	source $execDir/testLogExports.sh
	
	shuffP=$FAILURE_CODE
	if (($SHUFFLE_PROVIDER == 1));then
		shuffP=$SUCCESS_CODE
	fi
	
	shuffC=$FAILURE_CODE
	if (($SHUFFLE_CONSUMER == 1));then
		shuffC=$SUCCESS_CODE
	fi

	compression_=$FAILURE_CODE
	if (($COMPRESION_ == 1));then
		compression_="$SUCCESS_CODE &nbsp $COMPRESION_TYPE"  
	fi


	
	totalMappers=`echo "${DESIRED_MAPPERS}*${SLAVES_COUNT}" | bc`
	totalReducers=`echo "${DESIRED_REDUCERS}*${SLAVES_COUNT}" | bc`
	jobHeader="
			<tr bgcolor='LightSkyBlue'>
				<td colspan='6'>$exec - Shuffle-Pro. $shuffP, Shuffle-Con. $shuffC, Compression. $compression_, #Slaves: $SLAVES_COUNT, Data-set: ${tslDATA_SET}Gb, #Disks: $DISKS, #Samples: ${tslSAMPLES} <br> \
				Max tasks per node: ${MAX_MAPPERS} M, ${MAX_REDUCERS} R. Desired tasks per node: ${DESIRED_MAPPERS} M, ${DESIRED_REDUCERS} R. Totally desired tasks per execution: ${totalMappers} M, ${totalReducers} R</td>
			</tr>"
		
	echo "$echoPrefix: making statistics for the execution $exec"
	
		
	for test  in `ls $execDir | grep $TEST_DIR_PREFIX`
	do
		testDir=$execDir/$test
		if [ -f $testDir ];then
			continue
		fi
					
		source $testDir/execLogExports.sh
		
		jobSuccess=1
		jobWarn=0
		jobError=0
		jobFatal=0
		jobStatus=0
		#jobStatus=$successJobCode
		testNum=$((testNum+1))	
		historyLog=`find $testDir -maxdepth 1 -mindepth 1 -name *_h.txt`
				
		status=`grep "Status:" $historyLog | grep -c SUCCE`
		if (( $status == 1 ));then
			jobStatus=$SUCCESS_CODE
			jobStatusBGColor=$STANDARD_BGCOLOR
			jobStatusFontColor=$STANDARD_FONT_COLOR
		else
			jobStatus=$FAILURE_CODE
			jobStatusBGColor=$FATAL_BGCOLOR
			jobStatusFontColor=$FATAL_FONT_COLOR
			jobFatal=1
		fi
	
		coresBGColor=$STANDARD_BGCOLOR
		coresFontColor=$STANDARD_FONT_COLOR
		if (( $exlCORES != 0 )); then
			coresBGColor=$FATAL_BGCOLOR
			coresFontColor=$FATAL_FONT_COLOR
			jobFatal=1
		fi
		
		if (( $exlTERAVAL == 1 )); then
			teraval=$SUCCESS_CODE
			teravalBGColor=$STANDARD_BGCOLOR 
			teravalFontColor=$STANDARD_FONT_COLOR
		else
			teraval=$FAILURE_CODE
			teravalBGColor=$FATAL_BGCOLOR
			teravalFontColor=$FATAL_FONT_COLOR
			jobFatal=1
		fi
		if (( $exlIN_EQUAL_OUT == 1 )); then
			inputOutput=$SUCCESS_CODE
			inputOutputBGColor=$STANDARD_BGCOLOR 
			inputOutputFontColor=$STANDARD_FONT_COLOR 
		else
			inputOutput=$FAILURE_CODE
			inputOutputBGColor=$FATAL_BGCOLOR
			inputOutputFontColor=$FATAL_FONT_COLOR
			jobFatal=1
		fi
		
		getTime `grep "Finished At:" $historyLog`
		jobDuration=$getTimeRetVal
		
		mappersRecord=`grep -A 5 -m 1 "Task Summary" $historyLog | tail -n 1`
		reducersRecord=`grep -A 6 -m 1 "Task Summary" $historyLog | tail -n 1`
		
		getTime `echo $mappersRecord | tail -n 1`
		mapTime=$getTimeRetVal
		getTime `echo $reducersRecord | tail -n 1`
		reduceTime=$getTimeRetVal
		
		lunchedMappers=`echo $mappersRecord | awk 'BEGIN{FS=" "} {print $2}'`
		lunchedReducers=`echo $reducersRecord | awk 'BEGIN{FS=" "} {print $2}'`
		failedMappers=`echo $mappersRecord | awk 'BEGIN{FS=" "} {print $4}'`
		failedReducers=`echo $reducersRecord | awk 'BEGIN{FS=" "} {print $4}'`			
		killedMappers=`echo $mappersRecord | awk 'BEGIN{FS=" "} {print $5}'`
		killedReducers=`echo $reducersRecord | awk 'BEGIN{FS=" "} {print $5}'`

		failedMapBGColor=$STANDARD_BGCOLOR 
		killedMapBGColor=$STANDARD_BGCOLOR 
		failedReduceBGColor=$STANDARD_BGCOLOR 
		killedReduceBGColor=$STANDARD_BGCOLOR
		failedMapFontColor=$STANDARD_FONT_COLOR 
		killedMapFontColor=$STANDARD_FONT_COLOR 
		failedReduceFontColor=$STANDARD_FONT_COLOR 
		killedReduceFontColor=$STANDARD_FONT_COLOR

		if (( $failedMappers != 0 )); then 
			failedMapBGColor=$WARN_BGCOLOR
			failedMapFontColor=$WARN_FONT_COLOR
			jobWarn=1
		fi

		if (( $killedMappers != 0 )); then
			killedMapBGColor=$WARN_BGCOLOR
			killedMapFontColor=$WARN_FONT_COLOR
			jobWarn=1
		fi
	
		if (( $failedReducers != 0 )); then
			failedReduceBGColor=$ERROR_BGCOLOR
			failedReduceFontColor=$ERROR_FONT_COLOR
			jobError=1
		fi

		if (( $killedReducers != 0 )); then
			killedReduceBGColor=$ERROR_BGCOLOR
			killedReduceFontColor=$ERROR_FONT_COLOR
			jobError=1
		fi
		
		badMappers=`echo "scale=2; ${killedMappers}+${failedMappers}" | bc`
		badMappersPrecentage=`echo "(${badMappers}*100)/(${lunchedMappers}-${badMappers})" | bc`
		if (("$badMappersPrecentage" >= "$BAD_MAPPERS_THRESHOLD"));then
			jobError=1
			failedMapBGColor=$ERROR_BGCOLOR
			failedMapFontColor=$ERROR_FONT_COLOR
			killedMapBGColor=$ERROR_BGCOLOR
			killedMapFontColor=$ERROR_FONT_COLOR
		fi
		
		testsValues="$testsValues
			<tr> 
				<td>$testNum</td>
				<td bgcolor=$jobStatusBGColor><font color='$jobStatusFontColor'>$jobStatus</font></td>
				<td bgcolor=$coresBGColor><font color='$coresFontColor'>$exlCORES</font></td>
				<td>$jobDuration</td>
				<td>$exlDURATION_WITHOUT_FLUSH, 	$exlDURATION_WITH_FLUSH</td>
				<td>$mapTime</td>
				<td>$reduceTime</td>
				<td>$exlTERAGEN_COUNTER</td>
				<td bgcolor=$teravalBGColor><font color='$teravalFontColor'>$teraval</font></td>
				<td bgcolor=$inputOutputBGColor><font color='$inputOutputFontColor'>$inputOutput</font></td>
				<td>$lunchedMappers</td>
				<td bgcolor=$failedMapBGColor><font color='$failedMapFontColor'>$failedMappers</font></td>
				<td bgcolor=$killedMapBGColor><font color='$killedMapFontColor'>$killedMappers</font></td>
				<td>$lunchedReducers</td>
				<td bgcolor=$failedReduceBGColor><font color='$failedReduceFontColor'>$failedReducers</font></td>
				<td bgcolor=$killedReduceBGColor><font color='$killedReduceFontColor'>$killedReducers</font></td>
			</tr>"
		
		if (( $jobFatal == 1 ));then
			fatalDuration=$((fatalDuration+jobDuration))
			fatalCount=$((fatalCount+1))
			fatalArr[$fatalCount]=$jobDuration
			if (($jobDuration > $fatalMaxDuration));then
				fatalMaxDuration=$jobDuration
			fi
			if (($jobDuration < $fatalMinDuration));then
				fatalMinDuration=$jobDuration
			fi
		elif (( $jobError == 1 ));then
			errorDuration=$((errorDuration+jobDuration))
			errorCount=$((errorCount+1))
			errorArr[$errorCount]=$jobDuration
			if (($jobDuration > $errorMaxDuration));then
				errorMaxDuration=$jobDuration
			fi
			if (($jobDuration < $errorMinDuration));then
				errorMinDuration=$jobDuration
			fi
		elif (( $jobWarn == 1 ));then
			warnDuration=$((warnDuration+jobDuration))
			warnCount=$((warnCount+1))
			warnArr[$warnCount]=$jobDuration
			if (($jobDuration > $warnMaxDuration));then
				warnMaxDuration=$jobDuration
			fi
			if (($jobDuration < $warnMinDuration));then
				warnMinDuration=$jobDuration
			fi			
		elif (( $jobSuccess == 1 ));then
			successDuration=$((successDuration+jobDuration))
			successCount=$((successCount+1))
			successArr[$successCount]=$jobDuration
			if (($jobDuration > $successMaxDuration));then
				successMaxDuration=$jobDuration
			fi
			if (($jobDuration < $successMinDuration));then
				successMinDuration=$jobDuration
			fi
		else
			echo "$echoPrefix: there is no matching execution status!" | tee $ERROR_LOG
		fi			
	done #test
	currentDate=`date +"%Y-%m-%d_%H.%M.%S"`
	execTable="<table border='1' cellpadding='6' cellspacing='6' width='100%'>
				$TESTS_NAMES
				$testsValues
			</table>"
	execTableDir=$execDir/${REP_TERASORT_DATA_TABLE_FILE_NAME}_${currentDate}
	echo $execTable >> $execTableDir
	echo "$execTableDir" >> $REPORT_INPUT_DIR/analizeResults.txt
	
	# calculating statistics for the execution:
	
	statisticsSuccess=""
	if (($successCount != 0));then
		successAverage=`echo "scale=2; $successDuration/$successCount" | bc`
		stdDev $successCount $successAverage ${successArr[@]}
		successStdDev=$getStdDev

		statisticsSuccess="
		<tr bgcolor='$SUCCESS_BGCOLOR'>
			<font color='$SUCCESS_FONT_COLOR'>
				<td>Success tests:</td>
				<td>$successCount</td>
				<td>$successAverage</td>
				<td>$successMinDuration</td>
				<td>$successMaxDuration</td>
				<td>$successStdDev</td>
			</font>
		</tr>"
	fi
	
	statisticsWarn=""
	if (($warnCount != 0));then
		warnAverage=`echo "scale=2; $warnDuration/$warnCount" | bc`
		stdDev $warnCount $warnAverage ${warnArr[@]}
		warnStdDev=$getStdDev

		statisticsWarn="
		<tr bgcolor='$WARN_BGCOLOR'>
			<font color='$WARN_FONT_COLOR'>
				<td>Warn tests:</td>
				<td>$warnCount</td>
				<td>$warnAverage</td>
				<td>$warnMinDuration</td>
				<td>$warnMaxDuration</td>
				<td>$warnStdDev</td>
			</font>
		</tr>"
	fi
	
	statisticsError=""
	if (($errorCount != 0));then
		errorAverage=`echo "scale=2; $errorDuration/$errorCount" | bc`
		stdDev $errorCount $errorAverage ${errorArr[@]}
		errorStdDev=$getStdDev

		statisticsError="
		<tr bgcolor='$ERROR_BGCOLOR'>
			<font color='$ERROR_FONT_COLOR'>
				<td>Error tests:</td>
				<td>$errorCount</td>
				<td>$errorAverage</td>
				<td>$errorMinDuration</td>
				<td>$errorMaxDuration</td>
				<td>$errorStdDev</td>
			</font>
		</tr>"
	fi
	
	statisticsFatal=""
	if (($fatalCount != 0));then
		fatalAverage=`echo "scale=2; $fatalDuration/$fatalCount" | bc`
		stdDev $fatalCount $fatalAverage ${fatalArr[@]}
		fatalStdDev=$getStdDev
		
		statisticsFatal="
		<tr bgcolor='$FATAL_BGCOLOR'>
			<font color='$FATAL_FONT_COLOR'>
				<td>Fatal tests:</td>
				<td>$fatalCount</td>
				<td>$fatalAverage</td>
				<td>$fatalMinDuration</td>
				<td>$fatalMaxDuration</td>
				<td>$fatalStdDev</td>
			</font>
		</tr>"
	fi
	totalCount=$((successCount+warnCount+errorCount))
	totalAverage=`echo "scale=2; (${successDuration}+${warnDuration}+${errorDuration})/$totalCount" | bc`

	findMinDuration $successMinDuration $warnMinDuration $errorMinDuration
	totalMinDuration=$getMinDuration
	
	findMaxDuration $successMaxDuration $warnMaxDuration $errorMaxDuration
	totalMaxDuration=$getMaxDuration
	#totalMinDuration=$successMinDuration
	#if (($successMinDuration > $fatalMinDuration));then
	#	totalMinDuration=$fatalMinDuration
	#fi
	#totalMaxDuration=$fatalMaxDuration	
	#if (($successMaxDuration > $fatalMaxDuration));then
	#	totalMaxDuration=$successMaxDuration
	#fi
	totalArr=("${successArr[@]}" "${warnArr[@]}" "${errorArr[@]}")
	stdDev $totalCount $totalAverage ${totalArr[@]}
	TotalStdDev=$getStdDev
	
	statisticsTotal="
	<tr bgcolor='CornflowerBlue'>
		<td>TOTAL <font size="2">(valid only)</font>:</td>
		<td>$totalCount</td>
		<td>$totalAverage</td>
		<td>$totalMinDuration</td>
		<td>$totalMaxDuration</td>
		<td>$TotalStdDev</td>
	</tr>"
	
	statisticsValues="$statisticsSuccess $statisticsWarn $statisticsError $statisticsFatal $statisticsTotal"
	
	statisticsTable="<table border='1' cellpadding='7' cellspacing='7' width='100%'>
						$jobHeader
						$STATISTICS_NAMES
						$statisticsValues
					</table>"
	statisticsTableDir=$execDir/${REP_TERASORT_STAT_TABLE_FILE_NAME}_${currentDate}
	echo $statisticsTable >> $statisticsTableDir
	echo "$statisticsTableDir" >> $REPORT_INPUT_DIR/analizeResults.txt
		
	allTables="$allTables $statisticsTable $execTable <br><br>"

	unset successArr
	unset warnArr
	unset errorArr
	unset fatalArr
	unset totalArr
done