#!/bin/bash

# Written by Idan Weinstein
# Date: 2011-05-25


if [ $# -ne 2 ]; then
        echo "Usahge: ./`basename $0` <num of simultaneously mappers per TT> <num of simultaneously reducers per TT>"
	exit 1;
fi

if [ -z "$HADOOP_HOME" ]; then
        HADOOP_HOME=`pwd`
fi

#echo HADOOP_HOME=${HADOOP_HOME}


if [ -z "$HADOOP_CONF_DIR" ]; then
        HADOOP_CONF_DIR=${HADOOP_HOME}/conf
fi


awk -v m=$1 -v r=$2 '
BEGIN { 
	FS = "[<|>]"
	mapCategoryFound=0
	reduceCategoryFound=0
}
{

	if (mapCategoryFound == 1) {
        	sub($3,m)
		mapCategoryFound=0
	}

	if (reduceCategoryFound == 1) {
        	sub($3, r)
		reduceCategoryFound=0
	}
	if ($3 == "mapred.tasktracker.map.tasks.maximum") {
		mapCategoryFound=1
	}
	if ($3 == "mapred.tasktracker.reduce.tasks.maximum") {
		reduceCategoryFound=1
	}
	print
}' $HADOOP_CONF_DIR/mapred-site.xml >> $HADOOP_CONF_DIR/mapred-site.xml.new

echo "=============================="
echo "NEW values:"
echo "=============================="
cat $HADOOP_CONF_DIR/mapred-site.xml.new | grep -A 1 "tasks.max"
echo "=============================="

echo "*** saving old file as mapred-site.xml.old"
cp  $HADOOP_CONF_DIR/mapred-site.xml $HADOOP_CONF_DIR/mapred-site.xml.old
mv  $HADOOP_CONF_DIR/mapred-site.xml.new $HADOOP_CONF_DIR/mapred-site.xml


