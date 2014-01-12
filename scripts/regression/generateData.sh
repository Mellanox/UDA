
#!/bin/sh

echoPrefix=`eval $ECHO_PATTERN`
cmdBase=$1
dataDir=$2
generateCount=$3
dataLabel=$4


echo "$echoPrefix: ---------------------------------------"
echo "$echoPrefix: - Generating ${dataLabel} ${generateCount} times"
echo "$echoPrefix: - Number of slaves = $SLAVES_COUNT slaves"
echo "$echoPrefix: - Number of local disks per node = $DISKS_COUNT (counts seperated commas on hdfs-site.xml)"
echo "$echoPrefix: ---------------------------------------"

if [[ $@ == *rmr* ]] && ((`$HADOOP_FS -ls $dataDir | grep -c $dataLabel*` != 0));then
	eval $HADOOP_FS_RMR $dataDir/$dataLabel*
fi

failedGenerations=0

for i in `seq 1 $generateCount`; do
	outputDir=$dataDir/${dataLabel}.${i}
	if ((`$HADOOP_FS -ls / | grep -c $outputDir` == 1));then
		echo "$echoPrefix: the output dir $outputDir is already existing. skipping generating data"
		continue
	fi
	cmd="$cmdBase $outputDir"
	echo $cmd
	eval $cmd
	if (($? != 0)); then
		failedGenerations=1
	fi
	if (($TEST_RUN_FLAG == 1));then
		break
	fi
done

if [[ $@ == *clear* ]];then
	eval $HADOOP_FS_RMR $dataDir/$dataLabel*
fi

exit $failedGenerations
