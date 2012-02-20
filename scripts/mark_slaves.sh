#!/bin/bash
# Written by Idan Weinstein On 2011-7-19

if [ -z "$MY_HADOOP_HOME" ]
then
        echo $0: "please export MY_HADOOP_HOME"
        exit 1
fi


if [ -z "$HADOOP_CONF_DIR" ]
then
	HADOOP_CONF_DIR="$MY_HADOOP_HOME/conf"
fi


if [ -z "$1" ] || [ $1 -lt 2 ]
then
	echo "Usage: $(basename $0) <number of slaves to be marked as useable> (must be more 1)"
	exit 1;
fi

total_slave_rows=`grep -c "." $HADOOP_CONF_DIR/slaves` 
[ -z $total_slave_rows ] && total_slave_rows=0

if [ $1 -gt $total_slave_rows ]
then
	echo "$0: Error - $HADOOP_CONF_DIR/slaves contains $total_slave_rows marked/unmarked nodes ==> cannot mark more then that. please modify slaves file to add more hostnames"
	exit 1;
fi

rm -rf "$HADOOP_CONF_DIR/slaves.new"

nodes_count=0
for sl in `grep  "." $HADOOP_CONF_DIR/slaves`
do
	if [ $nodes_count -lt $1 ]
	then
		echo $sl |  sed 's/.*#//' >> "$HADOOP_CONF_DIR/slaves.new"
	else
		tmp=`echo $sl |  sed 's/.*#//'`
		echo "#"${tmp}  >> "$HADOOP_CONF_DIR/slaves.new"
	fi

	nodes_count=$(($nodes_count + 1))
done


rm -rf "$HADOOP_CONF_DIR/slaves.old"
mv  "$HADOOP_CONF_DIR/slaves" "$HADOOP_CONF_DIR/slaves.old"

code=0
code= mv "$HADOOP_CONF_DIR/slaves.new" "$HADOOP_CONF_DIR/slaves"

if [ ${code} != 0 ]
then
        echo $0: ERROR: failed to updates slaves file
        exit 1;
fi


exit 0;


