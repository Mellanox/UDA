#!/bin/sh

# Written by Idan Weinstein and Avner BenHanoch
# Date: 2011-04-15
# MODIFIED: 2011-05-25 by idan (added mappers&reduces scale)
# MODIFIED: 2011-07-06 by idan (added params shows , log_prefix modification)
# MODIFIED: 2011-07-20 by idan (added #nodes scale & retry mechanism)



export HADOOP_SLAVE_SLEEP=1
SCRIPTS_LOCAL_TMP_DIR=/tmp/hadoop/scripts
MAX_ATTEMPTS=5

if [ -z "$HADOOP_HOME" ]
then
        echo $(basename $0): "please export HADOOP_HOME"
        exit 1
fi

if [ -z "$RES_SERVER" ]
then
        echo "$(basename $0): please export RES_SERVER (the server to collect the results to)"
        exit 1
fi

if [ -z "$RES_LOGDIR" ]
then
        export RES_LOGDIR="/hadoop/results/my-log"
fi


#if [ -z $SCRIPTS_DIR ]
#then
	export SCRIPTS_DIR=$SCRIPTS_LOCAL_TMP_DIR
#fi


if [ -z "$HADOOP_CONF_DIR" ]
then
	export HADOOP_CONF_DIR=$HADOOP_HOME/conf
fi

if [ -z "$CLUSTER_NODES" ]
then
	CLUSTER_NODES="8 10 12"
fi 

if [ -z "$DATA_SET_TYPE" ]
then
	DATA_SET_TYPE=node
fi

if [ -z "$DATA_SET" ]
then
	DATA_SET="16"
fi

if [ -z "$NR" ]
then
	NR="4"
fi

if [ -z "$NM" ]
then
	NM="8"
fi

if [ -z "$NSAMPLES" ]
then
	NSAMPLES=3
fi

rdma="UNKNOWN"
merge_approach="UNKNOWN"
interface="UNKNOWN"
rdma=`grep -A 1 "rdma.setting" $HADOOP_CONF_DIR/mapred-site.xml | grep -c "<value>1</value>"`
merge_approach=`grep -A 1 "merge.approach" $HADOOP_CONF_DIR/mapred-site.xml | grep -c "<value>1</value>"`

if (( $merge_approach==0 ))
    then
	merge_approach=2
fi
interface=`grep -A 1 "mapred.tasktracker.dns.interface" $HADOOP_CONF_DIR/mapred-site.xml`

disks=$(cat $HADOOP_HOME/conf/mapred-site.xml | grep -A 1 ">mapred.tasktracker.dns.interface<")
aa=`echo $disks | awk 'BEGIN { FS = "name> <value>"} ; { print $2}'`
bb=`echo $aa | awk 'BEGIN { FS = "<"} ; { print $1}'`

hadoop_version=`echo $(basename $HADOOP_HOME) | sed s/[.]/_/g`

echo "$(basename $0): Dynamic Parameters: (that can be exported by user)"
echo "$(basename $0): ------------------------------------------"
echo "$(basename $0): HADOOP_HOME=$HADOOP_HOME"
echo "$(basename $0): HADOOP_CONF_DIR=$HADOOP_CONF_DIR"
echo "$(basename $0): RES_SERVER=$RES_SERVER (the host which the results will collected to)"
echo "$(basename $0): DATA_SET_TYPE=$DATA_SET_TYPE (node=size per node , cluster=size for whole cluster)" 
echo "$(basename $0): DATA_SET=$DATA_SET (list of size data sets in GB)" 
echo "$(basename $0): CLUSTER_NODES=$CLUSTER_NODES (#nodes list to scale)"
echo "$(basename $0): NR=$NR (list of #Reduce tasks per TT)"
echo "$(basename $0): NM=$NM (list of #Map tasks per TT"
echo "$(basename $0): NSAMPLES=$NSAMPLES (#Samples for each job)"
echo "$(basename $0): RES_LOGDIR=$RES_LOGDIR (the local path on '$RES_SERVER' that logs&stats will collected to'"
echo " "
echo "$(basename $0): Static Parameters: (that calculated by script and cannot be exported by user)"
echo "$(basename $0): ------------------------------------------"
echo "$(basename $0): SCRIPTS_DIR=$SCRIPTS_DIR (scripts will be copied to this local path on each node - unless -skip_nfs arg added)"
echo "$(basename $0): rdma.setting=$rdma"
echo "$(basename $0): merge_approach=$merge_approach"
echo "$(basename $0): hadoop version=$hadoop_version"
echo "$(basename $0): interface=$bb"

if [[ $@ = *-show* ]]
then
	exit 0;
fi

echo "press any to start..."
read -n1 kbd


if [[  $@ != *-skip_nfs* ]] 
then
	copy_succeed=1
	while ((copy_succeed!=0)) ; do
		echo "$(basename $0): copy the executed script's dir to local tmp directory for each node"
		sudo $(dirname $0)/copy_scripts_dir.sh
		copy_succeed=$?
		if ((copy_succeed!=0)) ; then
			echo $(basename $0): ERROR: failed to copy scripts dir to local tmp folders..try again
			sleep 5
		fi
	done
fi



cd $HADOOP_HOME


# check if slave's hostname are matching the same network interface (ib, 1g, 10g)

host=`head -1 $HADOOP_CONF_DIR/slaves`
host_tail=`[[  $host =~ "-" ]] && echo $host | sed 's/.*-//' || echo lan`
for host in `cat $HADOOP_CONF_DIR/slaves`; do
	if [ $host_tail !=  `[[  $host =~ "-" ]] && echo $host | sed 's/.*-//' || echo lan` ]
	then
		echo $(basename $0): slave\'s hostnames are not matching for the same network interface: `cat $HADOOP_CONF_DIR/slaves`
		exit 1;
	fi
done

if [ $host_tail == "lan" ]
then
	echo $(basename $0): ERROR: "slave\'s hostname are not tailed with network interface identifier (hostname-ib , hostname-1g or hostname-ib) hadoop traffic will use LAN interface"
	exit 1;
fi

echo "$(basename $0): Reset all marked/unmarked slaves"
total_slaves_rows=`grep -c "." $HADOOP_CONF_DIR/slaves`
$SCRIPTS_DIR/mark_slaves.sh $total_slaves_rows

$SCRIPTS_DIR/reset_all.sh
if (($?!=0))
then
	echo "$(basename $0): RESET_ALL FAILED"
	exit 1;
fi

for node_scale in ${CLUSTER_NODES} ; do

	disks=$((`cat $HADOOP_CONF_DIR/hdfs-site.xml | grep -A 1 ">dfs.data.dir<" | grep -o "," | wc -l | sed s/\ //g` + 1))
	log_prefix=${hadoop_version}.${host_tail}.rdma${rdma}.merge_approach${merge_approach}.${node_scale}n.${disks}d.$$
	
	echo "$(basename $0): Modify slaves conf file to enable $nodes_scale hostnames"
	$SCRIPTS_DIR/mark_slaves.sh $node_scale
	
	echo $(basename $0): Copy  conf dir to salves
        sudo ${SCRIPTS_DIR}/copy_conf.sh

	echo "$(basename $0): #slaves=$nodes"
	echo "$(basename $0): #spindles=$disks"
	echo "$(basename $0): log_perfix=$log_prefix"
	

	echo "$(basename $0): Restarting Hadoop"
	$SCRIPTS_DIR/start_hadoop.sh 5 -restart -teragen #5 retries
	code=$?
	if (($code!=0)) 
	then
		echo "$(basename $0): ERROR - failed to restart Hadoop"
		continue
	fi

	for sample in `seq 0 $((NSAMPLES-1))` ; do
		for nmaps in ${NM}; do
			for nreds in ${NR}; do
	
				echo $(basename $0): Modifing mapred-site.xml for ${nmaps} mappers and ${nreds} reducers per TT
				sudo ${SCRIPTS_DIR}/replace_conf_mapred.sh ${nmaps} ${nreds}
					
				echo $(basename $0): Copy  conf dir to salves
				sudo ${SCRIPTS_DIR}/copy_conf.sh
						
				for ds in ${DATA_SET}; do
					if (( ${nmaps} >= ${nreds})); then 
						
						echo $(basename $0): "Cleaning /terasort/output HDFS library"
						echo $(basename $0): bin/hadoop fs -rmr /terasort/output
						bin/hadoop fs -rmr /terasort/output
						sleep 10
						
						totalReducers=$(($node_scale * $nreds))
						if [ "$DATA_SET_TYPE" = "node" ]
						then
							totalDataSet=$(($ds * $node_scale))
						else
							totalDataSet=$ds
						fi
						
						echo "$(basename $0): Running test on cluster of $node_scale slaves with $nmaps mapers, $nreds reducers per TT and total of $totalReducers reducers"
						echo "$(basename $0): Cleaning buffer caches" 
						sudo bin/slaves.sh ${SCRIPTS_DIR}/cache_flush.sh
						#TODO: above will only flash OS cache; still need to flash disk cache
						sleep 3
	
						echo "$(basename $0): Cleaning logs directories (history&userlogs)"
						rm -rf $HADOOP_HOME/logs/userlogs/*
						rm -rf $HADOOP_HOME/logs/history/*
						bin/slaves.sh rm -rf $HADOOP_HOME/logs/userlogs/*
						bin/slaves.sh rm -rf $HADOOP_HOME/logs/history/*
		
						#this is the command to run
						export USER_CMD="bin/hadoop jar hadoop*examples*.jar terasort  -Dmapred.reduce.tasks=${totalReducers} /terasort/input/${totalDataSet}G /terasort/output"
						JOB=${log_prefix}.N${ds}G.N${nmaps}m.N${nreds}r.T${totalDataSet}G.T${totalReducers}r.log.${sample}
						
						attempt=0
						code=0
						attempt_code=1
						while ((attempt_code!=0)) && ((attempt<MAX_ATTEMPTS))
						do

							echo "$(basename $0): calling mr-dstat for $USER_CMD attempt $attempt"
							${SCRIPTS_DIR}/mr-dstat.sh "${JOB}_attempt${attempt}"
							attempt_code=$?
							if ((attempt_code!=0))
							then
								echo "$(basename $0): FAILED ${JOB}_attempt${attempt}"
								if ((attempt>1))
								then
									echo "$(basename $0): first attempt failed - restart hadoop without forcing DFS format"

								        ${SCRIPTS_DIR}/start_hadoop.sh 4 -teragen #4 retries
								        code=$?
								        if ((code!=0))
								        then
								                echo "$(basename $0): ERROR - failed to restart Hadoop"
								                continue
									fi
								else
									echo "$(basename $0): more then one attempt failed - restart hadoop AND FORCING DFS format"
								        ${SCRIPTS_DIR}/start_hadoop.sh 4 -restart -teragen #4 retries
									code=$?
								        if ((code!=0))
								        then
								                echo "$(basename $0): ERROR - failed to restart Hadoop"
								                continue
									fi
								fi
							fi

							attempt=$((attempt+1))

						done		
						
						if ((attempt_code=0))
						then
							echo "$(basename $0): ${JOB}_attempt${attempt} SUCCESS"
						fi
		
					else
						echo "$(basename $0): skip ${nmaps} mappers and ${nreds} reducers"
					fi	
				done
			done
		done
	done
done
