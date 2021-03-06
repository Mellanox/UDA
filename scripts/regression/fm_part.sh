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

#################### TEMPORARY - added by oriz at 9/4/13 ######################
       	     # THIS SCRIPT MUST BE RESEARCHED AND REWRITE ASAP #
if [[ $USER == "oriz" ]] || [[ $USER == "eladi"  ]]; then
	echo pdsh -w $SLAVES_BY_COMMAS "rm -rf  /data2/regression_data/data/* /data3/regression_data/data/* /data4/regression_data/data/* /data5/regression_data/data/*"
	pdsh -w $SLAVES_BY_COMMAS "rm -rf  /data2/regression_data/data/* /data3/regression_data/data/* /data4/regression_data/data/* /data5/regression_data/data/*"
fi
###############################################################################

disks=$(cat $MY_HADOOP_HOME/conf/core-site.xml | grep -A 1 ">hadoop.tmp.dir<")

aa=`echo $disks | awk 'BEGIN { FS = "name> <value>"} ; { print $2}'`

cc=`echo $aa | awk 'BEGIN { FS = "<"} ; { print $1}'`
echo $(basename $0): "removing $cc"

partitions=`echo $cc | sed 's/\,/\ /g'`
echo " partitions $partitions"
rm -rf $partitions
isRemoved=$?

if (( $isRemoved != 0 )); then
	echo "$(basename $0) couldn't remove $partitions core-site.xml exiting.... :("
	exit 5
fi

for part in $partitions; do
	last_char=`echo $part | sed 's/^.*\(.\{1\}\)$/\1/'`
	if [[ $last_char == "/" ]]; then
		part=${part%?}
	fi
	minus=`expr length ${part##*/}`
	ll=`expr length $part`; dir=${part:0:($ll-$minus)}; mkdir $dir/test; if (( $?!=0 )); then echo "cant write in $dir"; rm -rf $dir/test; exit 5; else rm -rf $dir/test; fi;
done

slaves=`cat $MY_HADOOP_HOME/conf/slaves`
for slave in $slaves; do

	ssh $slave rm -rf $partitions; isRemoved=$?; if ((  $isRemoved != 0 )); then echo "couldn't remove $partitions from $slave core-site.xml EXITING... ";  exit 0; fi
	for part in $partitions; do
		last_char=`echo $part | sed 's/^.*\(.\{1\}\)$/\1/'`
        	if [[ $last_char == "/" ]]; then
                	part=${part%?}
        	fi
        	minus=`expr length ${part##*/}`
        	ll=`expr length $part`; dir=${part:0:($ll-$minus)}; ssh $slave mkdir $dir/test; if (( $?!=0 )); then echo "cant write in $dir in $slave" ; ssh $slave rm -rf $dir/test; exit 5; else ssh $slave rm -rf $dir/test; fi;
	done

done


disks=$(cat $MY_HADOOP_HOME/conf/hdfs-site.xml | grep -A 1 ">dfs.data.dir<")

aa=`echo $disks | awk 'BEGIN { FS = "name> <value>"} ; { print $2}'`
cc=`echo $aa | awk 'BEGIN { FS = "<"} ; { print $1}'`
echo $(basename $0): "removing $cc"
bb=`echo $cc | awk 'BEGIN { FS = "," } ; { print NF }'`
partitions=`echo $cc | sed 's/\,/\ /g'`
echo " partitions $partitions"
rm -rf $partitions

isRemoved=$?

if (( $isRemoved != 0 )); then
	echo "$(basename $0) couldn't remove $partitions hdfs-site.xml exiting..... :( "
	exit 5
fi	

for part in $partitions; do
	last_char=`echo $part | sed 's/^.*\(.\{1\}\)$/\1/'`
        if [[ $last_char == "/" ]]; then
           part=${part%?}
        fi
        minus=`expr length ${part##*/}`
        ll=`expr length $part`; dir=${part:0:($ll-$minus)}; mkdir $dir/test; if (( $?!=0 )); then echo "cant write in $dir"; exit 5; else rm -rf $dir/test; fi;
done
	
slaves=`cat $MY_HADOOP_HOME/conf/slaves`
for slave in $slaves; do
	ssh $slave rm -rf $partitions; isRemoved=$?; if ((  $isRemoved != 0 )); then echo "couldn't remove $partitions from $slave hdfs-site.xml EXITING... ";  exit 0; fi
	for part in $partitions; do
		last_char=`echo $part | sed 's/^.*\(.\{1\}\)$/\1/'`
                if [[ $last_char == "/" ]]; then
                        part=${part%?}
                fi
                minus=`expr length ${part##*/}`
                ll=`expr length $part`; dir=${part:0:($ll-$minus)}; ssh $slave mkdir $dir/test; if (( $?!=0 )); then echo "cant write in $dir in $slave"; ssh $slave rm -rf $dir/test; exit 5; else ssh $slave rm -rf $dir/test; fi;
        done

done


disks=$(cat $MY_HADOOP_HOME/conf/hdfs-site.xml | grep -A 1 ">dfs.name.dir<")

aa=`echo $disks | awk 'BEGIN { FS = "name> <value>"} ; { print $2}'`
cc=`echo $aa | awk 'BEGIN { FS = "<"} ; { print $1}'`
echo $(basename $0): "removing $cc"

partitions=`echo $cc | sed 's/\,/\ /g'`
echo " partitions $partitions"
rm -rf $partitions
isRemoved=$?

if (( $isRemoved != 0 )); then
	echo "$(basename $0) couldn't remove $partitions hdfs-site.xml exiting.... :("
	exit 5
fi
	
for part in $partitions; do
	last_char=`echo $part | sed 's/^.*\(.\{1\}\)$/\1/'`
        if [[ $last_char == "/" ]]; then
             part=${part%?}
        fi
        minus=`expr length ${part##*/}`
        ll=`expr length $part`; dir=${part:0:($ll-$minus)}; mkdir $dir/test; if (( $?!=0 )); then echo "cant write in $dir in master"; exit 0; else rm -rf $dir/test; fi;
done

	
slaves=`cat $MY_HADOOP_HOME/conf/slaves`
for slave in $slaves; do
	ssh $slave rm -rf $partitions; isRemoved=$?; if ((  $isRemoved != 0 )); then echo "couldn't remove $partitions from $slave hdfs-site.xml EXITING... ";  exit 0; fi
	for part in $partitions; do
		last_char=`echo $part | sed 's/^.*\(.\{1\}\)$/\1/'`
                if [[ $last_char == "/" ]]; then
                        part=${part%?}
                fi
                minus=`expr length ${part##*/}`
                ll=`expr length $part`; dir=${part:0:($ll-$minus)}; ssh $slave mkdir $dir/test; if (( $?!=0 )); then echo "cant write in $dir in $slave"; ssh $slave rm -rf $dir/test;  exit 0; else ssh $slave rm -rf $dir/test; fi;
        done

done

 echo "$(basename $0) formating namenode"
        format_output=`eval $DFS_FORMAT 2>&1`
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
				echo NOT A GOOD FORMAT!! not all disks have been formated..
				exit 1;
			  fi
				

	done

	
	echo "--------->>><<<--------"
	
