#!/bin/sh

# Written by Idan Weinstein and Avner BenHanoch
# Date: 2011-04-15
# MODIFIED: 2011-05-25 by idan (added mappers&reduces scale)
# MODIFIED: 2011-07-06 by idan (added params shows , log_prefix modification)
# MODIFIED: 2011-07-20 by idan (added #nodes scale & retry mechanism)



#export HADOOP_SLAVE_SLEEP=1
SCRIPTS_LOCAL_TMP_DIR=/tmp/hadoop/scripts
MAX_ATTEMPTS=5

if [ -z "$MY_HADOOP_HOME" ]
then
        echo $(basename $0): "please export MY_HADOOP_HOME"
        exit 1
fi

	export SCRIPTS_DIR=$SCRIPTS_LOCAL_TMP_DIR


if [ -z "$HADOOP_CONF_DIR" ]
then
	export HADOOP_CONF_DIR=$MY_HADOOP_HOME/conf
fi

if [ -z "$DATA_SET_TYPE" ]
then
	export DATA_SET_TYPE=node
fi


#if [ -z "$EXCEL_LINE_NUM" ]
#then
#        export EXCEL_LINE_NUM=0
#fi

cd $MY_HADOOP_HOME


mkdir -p $SCRIPTS_DIR
cp -rf $(dirname $0)/* $SCRIPTS_DIR/


#echo "$(basename $0): awk -v conf_num=0 -v conf_dir=$HADOOP_CONF_DIR -f $SCRIPTS_DIR/create_terasort_conf.awk  $HADOOP_CONF_DIR/config_file.csv"
awk -v conf_num=0 -v conf_dir=$HADOOP_CONF_DIR -f ${SCRIPTS_DIR}/create_terasort_conf.awk $HADOOP_CONF_DIR/config_file.csv
if (($?!=0)) ; then echo error 1; exit 2; fi

export RES_SERVER=`cat $HADOOP_CONF_DIR/dataCollectorNode.txt`
export EXCEL_LINE_NUM=`cat $HADOOP_CONF_DIR/excelLineNumber.txt`
export RES_LOGDIR=`cat $HADOOP_CONF_DIR/logDir.txt`

hadoop_version=`echo $(basename $MY_HADOOP_HOME) | sed s/[.]/_/g`

echo "$(basename $0): Dynamic Parameters: (that can be exported by user)"
echo "$(basename $0): ------------------------------------------"
echo "$(basename $0): MY_HADOOP_HOME = $MY_HADOOP_HOME"
echo "$(basename $0): HADOOP_CONF_DIR = $HADOOP_CONF_DIR"
echo "$(basename $0): DATA_SET_TYPE = $DATA_SET_TYPE (node=size per node , cluster=size for whole cluster)"
#echo "$(basename $0): EXCEL_LINE_NUM=$EXCEL_LINE_NUM (number of lines in Excel configuration file we want to run) "
echo " "
echo "$(basename $0): Static Parameters: (that calculated by script and cannot be exported by user)"
echo "$(basename $0): ------------------------------------------"
echo "$(basename $0): SCRIPTS_DIR = $SCRIPTS_DIR (scripts will be copied to this local path on each node - unless -skip_nfs arg added)"
echo "$(basename $0): RES_SERVER = $RES_SERVER"
echo "$(basename $0): RES_LOGDIR = $RES_LOGDIR"
echo "$(basename $0): EXCEL_LINES_NUM = $EXCEL_LINE_NUM"


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
		$(dirname $0)/copy_scripts_dir.sh
		copy_succeed=$?
		if ((copy_succeed!=0)) ; then
			echo $(basename $0): ERROR: failed to copy scripts dir to local tmp folders..try again
			sleep 5
		fi
	done
fi




		echo "$SCRIPTS_DIR/copy_conf.sh"
		$SCRIPTS_DIR/copy_conf.sh

		for line in `seq 1 $((EXCEL_LINE_NUM))` ; do
			
			echo "-->>>   LINE IS: $line "
			echo "-->>>   LINE IS: $line "
			echo "-->>>   LINE IS: $line "
			echo "-->>>   LINE IS: $line "

			#echo " $(basename $0) rm -rf $HADOOP_CONF_DIR/slaves $HADOOP_CONF_DIR/mapred-site.xml $HADOOP_CONF_DIR/hdfs-site.xml $HADOOP_CONF_DIR/core-site"
			#rm -rf $HADOOP_CONF_DIR/slaves
			#rm -rf $HADOOP_CONF_DIR/mapred-site.xml
			#rm -rf $HADOOP_CONF_DIR/hdfs-site.xml
			#rm -rf $HADOOP_CONF_DIR/core-site.xml

			echo "awk -v conf_num=$line -v conf_dir=$HADOOP_CONF_DIR -f ${SCRIPTS_DIR}/create_terasort_conf.awk $HADOOP_CONF_DIR/config_file.csv"
			awk -v conf_num=$line -v conf_dir=$HADOOP_CONF_DIR -f ${SCRIPTS_DIR}/create_terasort_conf.awk $HADOOP_CONF_DIR/config_file.csv
			awk_answer=$?

			if (( $awk_answer==50 ))
			then 
			echo "line #$line is marked!!!! I'm skipping it..."; echo "line #$line is marked!!!! I'm skipping it..."; echo "line #$line is marked!!!! I'm skipping it..."; echo "line #$line is marked!!!! I'm skipping it..."; echo "line #$line is marked!!!! I'm skipping it..."; echo "line #$line is marked!!!! I'm skipping it...";

			continue
			fi
			
			mappers=`cat $HADOOP_CONF_DIR/mappersNum.txt`
			reducers=`cat $HADOOP_CONF_DIR/reducersNum.txt`
				
			#change:
			rdma=`grep -A 1 "rdma.setting" $HADOOP_CONF_DIR/mapred-site.xml | grep -c "<value>1</value>"`
	
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

			export CLUSTER_NODES=`cat $HADOOP_CONF_DIR/clusterNodesNum.txt`
			disks=$((`cat $HADOOP_CONF_DIR/hdfs-site.xml | grep -A 1 ">dfs.data.dir<" | grep -o "," | wc -l | sed s/\ //g` + 1))
			export DATA_SET=`cat $HADOOP_CONF_DIR/dataSetSize.txt`
			export NSAMPLES=`cat $HADOOP_CONF_DIR/samplesNum.txt`
			export TERAVALIIDATE=`cat $HADOOP_CONF_DIR/teravalidate.txt`
			
			echo "------------------------------------------------------------"
			echo "********** line is:  $line  *******************************"
			echo "********** DATA_SET=  $DATA_SET   *************************"
			echo "********** CLUSTER_NODES= $CLUSTER_NODES  *****************"
                        echo "********** MAPPERS= $mappers  *****************************"
                        echo "********** REDUCERS= $reducers  ***************************"
			echo "********** NSAMPLES= $NSAMPLES ****************************"
			echo "********** TERAVALIIDATE = $TERAVALIIDATE ****************************"			
			echo "-----------------------------------------------------------"

			for node_scale in ${CLUSTER_NODES} ; do

			#        disks=$((`cat $HADOOP_CONF_DIR/hdfs-site.xml | grep -A 1 ">dfs.data.dir<" | grep -o "," | wc -l | sed s/\ //g` + 1))

       				 log_prefix=${hadoop_version}.$line.${host_tail}.rdma${rdma}.merge_approach${merge_approach}.${node_scale}n.${disks}d.$$

        			echo "$(basename $0): Modify slaves conf file to enable $nodes_scale hostnames"
        			$SCRIPTS_DIR/mark_slaves.sh $node_scale

        			echo $(basename $0): Copy  conf dir to salves
        			${SCRIPTS_DIR}/copy_conf.sh
        			echo "$(basename $0): #slaves=$CLUSTER_NODES"
        			echo "$(basename $0): #spindles=$disks"
			        echo "$(basename $0): log_perfix=$log_prefix"

        			echo "$(basename $0): Restarting Hadoop"
       			        $SCRIPTS_DIR/start_hadoopExcel.sh 5 -restart -teragen #5 retries
        			code=$?
        			if (($code!=0))
        				then
                			echo "$(basename $0): ERROR - failed to restart Hadoop"
                			continue
        			fi

				for sample in `seq 0 $((NSAMPLES-1))` ; do				
					echo $(basename $0): Copy  conf dir to salves
					${SCRIPTS_DIR}/copy_conf.sh
						
					for ds in ${DATA_SET}; do
						if (( ${mappers} >= ${reducers})); then 
						
							attempt=0
							code=0
							attempt_code=1
							while ((attempt_code!=0)) && ((attempt<MAX_ATTEMPTS))
							do

							echo $(basename $0): "Cleaning /terasort/output HDFS library"
	                                                echo $(basename $0): bin/hadoop fs -rmr /terasort/output
	                                                bin/hadoop fs -rmr /terasort/output
	                                                sleep 10
	
	                                                totalReducers=$(($node_scale * $reducers))
	                                                if [ "$DATA_SET_TYPE" = "node" ]
	                                                then
	                                                        totalDataSet=$(($ds * $node_scale))
	                                                else
	                                                        totalDataSet=$ds
	                                                fi
	
	                                                echo "$(basename $0): Running test on cluster of $node_scale slaves with $mappers mapers, $reducers reducers per TT and total of $totalReducers reducers"
	                                                echo "$(basename $0): Cleaning buffer caches" 
	                                                sudo bin/slaves.sh ${SCRIPTS_DIR}/cache_flush.sh
	                                                #TODO: above will only flash OS cache; still need to flash disk cache
	                                                sleep 3
	
	                                                echo "$(basename $0): Cleaning logs directories (history&userlogs)"
	                                                rm -rf $MY_HADOOP_HOME/logs/userlogs/*
	                                                rm -rf $MY_HADOOP_HOME/logs/history/*
	                                                bin/slaves.sh rm -rf $MY_HADOOP_HOME/logs/userlogs/*
	                                                bin/slaves.sh rm -rf $MY_HADOOP_HOME/logs/history/*
	
	                                                #this is the command to run
	                                                export USER_CMD="bin/hadoop jar hadoop*examples*.jar terasort /terasort/input/${totalDataSet}G /terasort/output"
							export INPUTDIR="/terasort/input/${totalDataSet}G"

							echo "JOB=${log_prefix}.N${ds}G.N${mappers}m.N${reducers}r.T${totalDataSet}G.T${totalReducers}r.log.${sample}"
	                                                JOB=${log_prefix}.N${ds}G.N${mappers}m.N${reducers}r.T${totalDataSet}G.T${totalReducers}r.log.${sample}
	
							echo "$(basename $0): calling mr-dstat for $USER_CMD attempt $attempt"
							${SCRIPTS_DIR}/mr-dstatExcel.sh "${JOB}_attempt${attempt}"
							attempt_code=$?
							if ((attempt_code!=0))
							then
								echo "$(basename $0): FAILED ${JOB}_attempt${attempt}"
								if ((attempt>1))
								then
									echo "$(basename $0): first attempt failed - restart hadoop without forcing DFS format"

								        ${SCRIPTS_DIR}/start_hadoopExcel.sh 4 -teragen #4 retries
								        code=$?
								        if ((code!=0))
								        then
								                echo "$(basename $0): ERROR - failed to restart Hadoop"
								                continue
									fi
								else
									echo "$(basename $0): more then one attempt failed - restart hadoop AND FORCING DFS format"
								        ${SCRIPTS_DIR}/start_hadoopExcel.sh 4 -restart -teragen #4 retries
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

                echo "";  echo ""; echo ""; echo ""; echo ""; echo ""; echo ""; echo ""; echo ""; echo "";
                echo "finished line # $line!!!!!!!"
		echo "Deleting all Old directories!!!"
		echo "${SCRIPTS_DIR}/deleteOldDirectories.sh"
		${SCRIPTS_DIR}/deleteOldDirectories.sh
                echo ""; echo ""; echo ""; echo ""; echo ""; echo ""; echo ""; echo ""; echo ""; echo ""; echo "";

	done
