#!/bin/sh

#Writen by: Idan Weinstein
#Date: 25-5-2011 

cd $MY_HADOOP_HOME

if [ -z "$DATA_SET_TYPE" ]
then
        DATA_SET_TYPE=node
fi

nodes=`cat "$HADOOP_CONF_DIR/slaves" | grep ^[[:alnum:]] -c`

for i in $TOTAL_DATA_SET; do 
	if [ "$DATA_SET_TYPE" = "node" ]
	then
		finalDataSet=$finalDataSet" "$(($i*nodes)); 
	else
		finalDataSet=$finalDataSet" "$i
	fi
done


if (($nodes == 0)); then
        echo "Failed to calculate the number of slaves (using \'$MY_HADOOP_HOME\slaves\' file)"
fi

disks=$((`cat $HADOOP_CONF_DIR/hdfs-site.xml | grep -A 1 ">dfs.data.dir<" | grep -o "," | wc -l | sed s/\ //g` + 1))

if (($disks == 0)); then
        echo "Failed to calculate the number of disks (using \'$MY_HADOOP_HOME\hdfs-site.xml\' file , value of \'dfs.data.dir'\)"
fi

nmaps=$((nodes*MAX_MAPPERS))

<<C
echo "$0: TeraGen - Dynamic Parameters (user can export)"
echo "$0: TeraGen ---------------------------------------"
echo "$0: TeraGen - DATA_SET_TYPE=$DATA_SET_TYPE (node=size per node , cluster=size for whole cluster)"
echo "$0: TeraGen - DATA_SET=$TOTAL_DATA_SET"
echo ""
echo "$0: TeraGen - Static Parameters (user can not export)"
echo "$0: TeraGen ---------------------------------------"
echo "$0: TeraGen - DATA_SET_TOTAL=$finalDataSet (data set size for whole cluster)"
echo "$0: TeraGen - Number of saves = $nodes slaves"
echo "$0: TeraGen - Number of local disks per node = $disks (counts seperated commas on hdfs-site.xml)"
echo "$0: TeraGen - -Dmapred.map.tasks=${nmaps}"
C
echo "$0: TeraGen ---------------------------------------"
echo "$0: TeraGen - Date Set is $finalDataSet"
echo "$0: TeraGen - Number of saves = $nodes slaves"
echo "$0: TeraGen - Number of local disks per node = $disks (counts seperated commas on hdfs-site.xml)"
echo "$0: TeraGen - -Dmapred.map.tasks=${nmaps}"
echo "$0: TeraGen ---------------------------------------"

if [ "$1" == "-show" ]
then
        exit 0;
fi


if [[ $@ == "*-rmr*" ]]
then
	echo bin/hadoop fs -rmr $TERAGEN_DIR
	bin/hadoop fs -rmr $TERAGEN_DIR
fi


n=0
# for shorter execution:
#if (($SLAVES_COUNT == 1))
#then
# finalDataSet="2"
#else
# finalDataSet="4"
#fi
#echo "$0: NEW finalDataSet=$finalDataSet"

for i in ${finalDataSet}; do
	n=$((n+1))
	size=$((i * 10000000))
	echo bin/hadoop jar hadoop*examples*.jar teragen -Dmapred.map.tasks=${nmaps} ${size} $TERAGEN_DIR/${i}G.${n}
	bin/hadoop jar hadoop*examples*.jar teragen -Dmapred.map.tasks=${nmaps} ${size} $TERAGEN_DIR/${i}G.${n}
	if (($TEST_RUN_FLAG == 1));then
		break
	fi
done



