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
bb=`echo $cc | awk 'BEGIN { FS = "," } ; { print NF }'`

partitions=`echo $cc | sed 's/\,/\ /g'`
echo " partitions $partitions"
rm -rf $partitions
$MY_HADOOP_HOME/bin/slaves.sh  rm -rf $partitions

disks=$(cat $MY_HADOOP_HOME/conf/hdfs-site.xml | grep -A 1 ">dfs.data.dir<")

aa=`echo $disks | awk 'BEGIN { FS = "name> <value>"} ; { print $2}'`
cc=`echo $aa | awk 'BEGIN { FS = "<"} ; { print $1}'`
echo $(basename $0): "removing $cc"

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





	
