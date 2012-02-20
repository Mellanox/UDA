#!/bin/bash
# Written by Idan Weinstein On 2011-7-19

if [ -z "$MY_HADOOP_HOME" ]
then
        echo $0: "please export MY_HADOOP_HOME"
        exit 1
fi


if [ -z "$SCRIPTS_DIR" ]
then
        echo $0: "please export SCRIPTS_DIR"
        exit 1
fi

if [ -z "$HADOOP_CONF_DIR" ]
then
	HADOOP_CONF_DIR="$MY_HADOOP_HOME/conf"
fi

#changing interface in core-site.xml and mapred-site.xml
current_datanode=`hostname`
base_datanode=`hostname | sed 's/-.*//'`

if [ -z ${1} ]; then
        new_datanode=$base_datanode
else
        new_datanode="$base_datanode-${1}"
fi
sed "s/$current_datanode/$new_datanode/" -i $HADOOP_CONF_DIR/mapred-site.xml
sed "s/$current_datanode/$new_datanode/" -i $HADOOP_CONF_DIR/core-site.xml
sed "s/$current_datanode/$new_datanode/" -i $HADOOP_CONF_DIR/master





sudo ${SCRIPTS_DIR}/switch_hostname.sh ${1}
sudo bin/slaves.sh "${SCRIPTS_DIR}/switch_hostname.sh" ${1}

rm -rf "$HADOOP_CONF_DIR/slaves.new"

for slave in `cat $HADOOP_CONF_DIR/slaves` ; do
	base_h=$(echo $slave | sed 's/-.*//')

	if [ -z ${1} ]; then
	        echo ${base_h} >> $HADOOP_CONF_DIR/slaves.new
	else
		echo ${base_h}-${1} >> $HADOOP_CONF_DIR/slaves.new
	fi
done

if [ $(grep -c '.' $HADOOP_CONF_DIR/slaves.new) -ne  $(grep -c '.' $HADOOP_CONF_DIR/slaves) ]
then
	echo $0: ERROR: failed to updates slaves file
	exit 1;
fi

rm -rf "$HADOOP_CONF_DIR/slaves"

code=0
code= mv "$HADOOP_CONF_DIR/slaves.new" "$HADOOP_CONF_DIR/slaves"

if [ ${code} != 0 ]
then
        echo $0: ERROR: failed to updates slaves file
        exit 1;
fi


exit 0;


