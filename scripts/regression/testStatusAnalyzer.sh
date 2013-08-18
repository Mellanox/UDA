#!/bin/bash

checkFallback()
{
	fallbackDesc="$1"
	if [ `$sshPrefix cat $testDir/slave*/userlogs/job*/attempt*r*/syslog | grep fallback | grep -c "$fallbackDesc"` -ne 0 ];then
		retVal=0
	else
		retVal=1
	fi
}

memoryAllocationAnalyzer()
{
	rdmaSizeDest=$1
	retVal=0
	if (($SHUFFLE_CONSUMER == 0));then
		echo "export TEST_ERROR='UDA DID NOT RUN'" >> $testExports
		return 0
	fi
	
	bufferSizes="`$sshPrefix grep -rh "After RDMA memory" slave*/userlogs/job*/attempt*r*/syslog | awk '{ split($9,a,"="); print a[2] }' | sort -u`"
	if [[ -z $bufferSizes ]];then
		return 0
	fi
	for rdmaInBytes in $bufferSizes
	do
		#rdmaInBytes=`echo \"${record}\" | awk 'BEGIN{} {print $12}'`
		echo "$echoPrefix: the allocated rdma buffers size is ${rdmaInBytes} byts"
		rdmaInKb=`echo "$rdmaInBytes/1024" | bc`
		echo "$echoPrefix: the allocated rdma buffers size is ${rdmaInKb}Kb"
		
		if [[ $rdmaSizeDest == "max" ]];then
			if (($rdmaInKb != $RDMA_BUF_SIZE));then
				return 0
			fi
		elif [[ $rdmaSizeDest == "mid" ]];then
			if (($RDMA_BUF_SIZE_MIN > $rdmaInKb)) || (($rdmaInKb >= $RDMA_BUF_SIZE));then
				return 0
			fi
		else
			return 0
		fi
	done

	retVal=1		
}

memoryAllocationForCompressionAnalyzer() 
{

#"init compression configured. allocating rdmaBufferUsed=%d, uncompBufferUsed=%d totalBufferPerMof=%ld, splitPercentRdmaComp=%f", uncompBufferHardMin, totalBufferPerMof, splitPercentRdmaComp);

	retVal=0
	buffersSizesMessages="`$sshPrefix grep -rh "init compression configured. allocating" $testDir/slave*/userlogs/job*/attempt*r*/syslog`"
	uncompBufferUsed=`echo $buffersSizesMessages | awk 'BEGIN{} {print $11}' | sort -u`
	rdmaBufferUsed=`echo $buffersSizesMessages | awk 'BEGIN{} {print $11}' | sort -u`
	
	#echo "uncompBufferUsed values are: $uncompBufferUsed"
	#echo "rdmaBufferUsed values are: $rdmaBufferUsed"			
	echo THE buffersSizesMessages IS: $buffersSizesMessages
}

setupCompressionAnalyzer()
{
	compressionValid=1
	
	checkStatus "$exlTEST_STATUS"
	
	if (($retVal == 1));then
		retVal=0
		if [[ -z $COMPRESSION ]];then
			compressionValid=0
		elif [[ $COMPRESSION == "Snappy" ]];then
			count=`$sshPrefix  grep -c "INFO snappy.LoadSnappy: Snappy native library loaded" $testDir/testOutput.txt`
			echo count of snappy is: $count
			if (($count != 1));then
				compressionValid=0
			fi
		elif [[ $COMPRESSION == "Lzo" ]];then
			count=`$sshPrefix grep -c 'INFO compress.CodecPool: Got brand-new compressor' $testDir/testOutput.txt`
			echo count of LZO is: $count
			if (($count != 1));then
				compressionValid=0
			fi
		else
			compressionValid=0
		fi
		
		if (($compressionValid==1));then
			echo "$echoPrefix: installation of the compression is valid"
			retVal=1
		fi
	else
		echo "$echoPrefix: the test failed - it possible that the compression installation is corrupted"
		retVal=0
	fi
}

checkUdaIsUp()
{
	retVal=0
	local providerVersions=`$sshPrefix grep -h 'The version is' $testDir/slave*/hadoop*tasktracker*log* | awk 'BEGIN{} {print $8}' | sort -u`
	local consumerVersions=`$sshPrefix grep -h 'UDA version is' $testDir/slave*/userlogs/job*/attempt*r*/syslog | awk 'BEGIN{} {print $8}' | sort -u`
	local providerVersionsCount=`echo "$providerVersions" | awk 'BEGIN{RS=FS;count=0} {if ($1 ~ /[0-9.-]+/){count++}} END{print count}'`
	local consumerVersionsCount=`echo "$consumerVersions" | awk 'BEGIN{RS=FS;count=0} {if ($1 ~ /[0-9.-]+/){count++}} END{print count}'`
	
	if (($providerVersionsCount > 1)) || (($consumerVersionsCount > 1)) ;then
	echo "export TEST_ERROR='UDA providers or consumers have more than one UDA version'" >> $testExports
		checkUdaIsUpRetVal_rpmVersion="-1"
		return 0
	fi
	
	if [[ $providerVersions != $consumerVersions ]];then
		echo "export TEST_ERROR='UDA providers or consumers have differant UDA versions'" >> $testExports
		checkUdaIsUpRetVal_rpmVersion="-1"
		return 0
	fi
	
	if [[ -n $providerVersions ]] && [[ -n $consumerVersions ]] ;then
		retVal=1
	else
		echo "export TEST_ERROR='UDA providers or consumers were not loaded'" >> $testExports
		return 0
	fi
	
	checkUdaIsUpRetVal_rpmVersion=$providerVersions
}

checkConsumerIsUp()
{
	retVal=0
	
	local consumerVersions=`$sshPrefix grep -h 'UDA version is' $testDir/slave*/userlogs/job*/attempt*r*/syslog | awk 'BEGIN{} {print $8}' | sort -u`
	local consumerVersionsCount=`echo "$consumerVersions" | awk 'BEGIN{RS=FS;count=0} {if ($1 ~ /[0-9.-]+/){count++}} END{print count}'`
	
	if (($consumerVersionsCount > 1)) ;then
	echo "export TEST_ERROR='UDA consumers have more than one UDA version'" >> $testExports
		#checkUdaIsUpRetVal_rpmVersion="-1"
		return 0
	fi
	
	if [[ -n $consumerVersions ]] ;then
		retVal=1
	else
		echo "export TEST_ERROR='UDA consumers were not loaded'" >> $testExports
		return 0
	fi
	#checkUdaIsUpRetVal_rpmVersion="-1"
}

rpmInstallationAnalyzer()
{
	retVal=2
	if [[ $checkUdaIsUpRetVal_rpmVersion == $RPM_VERSION ]];then
		retVal=3
	else
		echo "export TEST_ERROR='UDA practical version is different than the configured version'" >> $testExports
	fi
}

inverseRetVal()
{
	retVal=$((1-retVal))
}

checkStatus()
{
	successCriteria=$1
	
	#eval successCriteriaValue=\$$successCriteria # getting the value of the variable with "inside" successCriteria
	#if (($successCriteriaValue == 1));then
	if (($successCriteria == 1));then
		retVal=1
	else
		retVal=0
	fi
}

managePerformanceTests()
{
	checkStatus "$exlTEST_STATUS"
	performanceTestFlag=1
}

testToAnalyzerMapper()
{
	testID=$1
	
	# VUDA-43: some temporary line till writnig general solution
	if [[ $testID == "VUDA-00" ]];then
		managePerformanceTests
		mapperRetVal=$retVal
		return 0
	fi
	
	if [[ $testID == "VUDA-43" ]];then 
		checkConsumerIsUp
		if (($retVal == 0));then
			mapperRetVal=$retVal
			return 0
		fi
		checkFallback
		inverseRetVal
		mapperRetVal=$retVal
		return 0
	fi

	if [[ $testID == "VUDA-35" ]];then 
		checkUdaIsUp
		if (($retVal == 0));then
			mapperRetVal=$retVal
			return 0
		fi
		checkFallback "illegal fetch request size of 0 or less bytes"
		inverseRetVal
		mapperRetVal=$retVal
		return 0
	fi

	if [[ -n $COMPRESSION ]] && [[ $PROGRAM != "pi" ]] ;then	
		setupCompressionAnalyzer
		if (($retVal == 0));then
				mapperRetVal=$retVal
				return 0
		fi
	fi

	checkUdaIsUp
	if (($retVal == 0));then
		mapperRetVal=$retVal
		return 0
	fi
	checkFallback
	case ${testID} in
		VUDA-11|VUDA-16|VUDA-20|VUDA-32|VUDA-33|VUDA-34|VUDA-36|VUDA-46	) inverseRetVal ;;
		VUDA-35|VUDA-46 ) memoryAllocationForCompressionAnalyzer ;;
		*	)
			if (($retVal == 0));then
				mapperRetVal=$retVal
				return 0
			fi
			case ${testID} in
				VUDA-17	) memoryAllocationAnalyzer "mid" ;;
				VUDA-19	) memoryAllocationAnalyzer "max" ;;
				VUDA-30	) setupCompressionAnalyzer;;
				VUDA-31	) rpmInstallationAnalyzer;;
				VUDA-21|VUDA-9|VUDA-12|VUDA-47	) checkStatus "$exlTEST_STATUS";;
				VUDA-29	) managePerformanceTests;;
				*	) echo "$testID has no Analyzer function" ;;   # Default.	
			esac
	esac
	
	mapperRetVal=$retVal
}

echoPrefix=`eval $ECHO_PATTERN`
testDir=$1
performanceTestFlag=0

sshPrefix=""
if [[ $RES_SERVER != `hostname` ]];then
	sshPrefix="ssh $RES_SERVER"
fi

testExports=$testDir/execLogExports.sh
source $testExports

testToAnalyzerMapper $TEST_IDS

echo "export PERFORNAMCE_TEST=$performanceTestFlag" >> $testExports

if (($mapperRetVal == 0));then
        echo "export TEST_STATUS=0" >> $testExports
elif (($mapperRetVal == 1));then
        echo "export TEST_STATUS=1" >> $testExports
elif (($mapperRetVal == 2));then
        echo "export TEST_STATUS=0" >> $testExports
        echo "export SETUP_FAILURE=1" >> $testExports
elif (($mapperRetVal == 3));then
        echo "export TEST_STATUS=1" >> $testExports
        echo "export SETUP_FAILURE=" >> $testExports # SETUP_FAILURE is null
fi

