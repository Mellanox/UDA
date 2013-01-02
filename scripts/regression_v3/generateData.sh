#!/bin/sh

echoPrefix=`eval $ECHO_PATTERN`
cmdBase=$1
dataDir=$2

echo "$echoPrefix: ---------------------------------------"
echo "$echoPrefix: - Generating ${DATA_LABEL} ${GENERATE_COUNT} times"
echo "$echoPrefix: - Number of slaves = $SLAVES_COUNT slaves"
echo "$echoPrefix: - Number of local disks per node = $DISKS_COUNT (counts seperated commas on hdfs-site.xml)"
echo "$echoPrefix: ---------------------------------------"

if [[ $@ == *rmr* ]] && ((`bin/hadoop fs -ls $dataDir | grep -c $DATA_LABEL*` != 0));then
	echo bin/hadoop fs -rmr $dataDir/$DATA_LABEL*
	bin/hadoop fs -rmr $dataDir/$DATA_LABEL*
fi

for i in `seq 1 $GENERATE_COUNT`; do
	outputDir=$dataDir/${DATA_LABEL}.${i}
	if ((`bin/hadoop fs -ls / | grep -c $outputDir` == 1));then
		echo "$echoPrefix: the output dir $outputDir is already existing. skipping generating data"
		continue
	fi
	cmd="$cmdBase $outputDir"
	echo $cmd
	eval $cmd
	if (($TEST_RUN_FLAG == 1));then
		break
	fi
done

if [[ $@ == *clear* ]];then
	echo bin/hadoop fs -rmr $dataDir/$DATA_LABEL*
	bin/hadoop fs -rmr $dataDir/$DATA_LABEL*
fi
