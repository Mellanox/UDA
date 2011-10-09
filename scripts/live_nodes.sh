#!/bin/sh

#Writen by: Katya Katsenelenbogen
#Date: 19-7-2011

if [ -z "$HADOOP_HOME" ]
then
        echo "please export HADOOP_HOME"
        exit 1
fi

cd $HADOOP_HOME

bin/hadoop fsck -racks | grep "Number of data-nodes"
tt_num=`bin/hadoop job -list-active-trackers 2>/dev/null | grep "tracker" -c`

echo " Number of task-trackers:          "$tt_num
