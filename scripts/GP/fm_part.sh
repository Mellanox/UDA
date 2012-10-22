#!/bin/bash
#
##Writen by: Shani
##Date: 29-8-2011
#

if [ -z "$MY_HADOOP_HOME" ]
then
        echo $(basename $0): "please export MY_HADOOP_HOME"
        exit 1
fi

disks=$(cat $MY_HADOOP_HOME/conf/core-site.xml | grep -A 1 ">hadoop.tmp.dir<")

aa=`echo $disks | awk 'BEGIN { FS = "name> <value>"} ; { print $2}'`

cc=`echo $aa | awk 'BEGIN { FS = "<"} ; { print $1}'`
echo $(basename $0): "removing $cc"
#bb=`echo $cc | awk 'BEGIN { FS = "," } ; { print NF }'`

partitions=`echo $cc | sed 's/\,/\ /g'`
echo " partitions $partitions"
rm -rf $partitions
$MY_HADOOP_HOME/bin/slaves.sh  rm -rf $partitions

disks=$(cat $MY_HADOOP_HOME/conf/hdfs-site.xml | grep -A 1 ">dfs.data.dir<")

aa=`echo $disks | awk 'BEGIN { FS = "name> <value>"} ; { print $2}'`
cc=`echo $aa | awk 'BEGIN { FS = "<"} ; { print $1}'`
echo $(basename $0): "removing $cc"
bb=`echo $cc | awk 'BEGIN { FS = "," } ; { print NF }'`
partitions=`echo $cc | sed 's/\,/\ /g'`
echo " partitions $partitions"
rm -rf $partitions
$MY_HADOOP_HOME/bin/slaves.sh  rm -rf $partitions

disks=$(cat $MY_HADOOP_HOME/conf/hdfs-site.xml | grep -A 1 ">dfs.name.dir<")

aa=`echo $disks | awk 'BEGIN { FS = "name> <value>"} ; { print $2}'`
cc=`echo $aa | awk 'BEGIN { FS = "<"} ; { print $1}'`
echo $(basename $0): "removing $cc"

partitions=`echo $cc | sed 's/\,/\ /g'`
echo " partitions $partitions"
rm -rf $partitions
$MY_HADOOP_HOME/bin/slaves.sh  rm -rf $partitions



 echo "$(basename $0) formating namenode"
        format_output=`hadoop namenode -format 2>&1`
        echo $format_output

        if [[ $format_output != *successfully* ]]
        then
                echo "$(basename $0): ERROR - failed to format DFS"
                exit 1;
        fi
        sleep 6

echo


	echo $format_output | while read line
	do
		for word in $line
		do
			#echo $word
			if [ $word == "successfully" ]
			then
				let counter=counter+1
				if [ $counter == $bb ]
				then
				#    echo GREAT FORMAT!!
				break
				fi
				
				declare -i counter2
			fi
		done
		declare -i counter2
		echo "Number of formats": $counter
                          if [ $counter == $bb ]
                          then
                               echo GREAT FORMAT ALL DISKS FORMATTED!!
                          else
				echo NOT A GOOD FORMAT!!
				exit 1;
			  fi
				

	done


	
