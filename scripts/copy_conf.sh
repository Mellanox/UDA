#!/bin/bash

# Written by Idan Weinstein
# Date: 2011-05-25


if [ -z "$MY_HADOOP_HOME" ]; then
	MY_HADOOP_HOME=`pwd`
fi

#echo MY_HADOOP_HOME=${MY_HADOOP_HOME}


if [ -z "$HADOOP_CONF_DIR" ]; then
	HADOOP_CONF_DIR=${MY_HADOOP_HOME}/conf
fi

#echo HADOOP_CONF_DIR=${HADOOP_CONF_DIR}

for s in `cat ${HADOOP_CONF_DIR}/slaves | grep -v '#'`; do
	#bin/slaves.sh scp -r `hostname`:${HADOOP_CONF_DIR}/* ${HADOOP_CONF_DIR}/
	echo scp -r ${HADOOP_CONF_DIR} ${s}:${MY_HADOOP_HOME}/
	scp -r ${HADOOP_CONF_DIR} ${s}:${MY_HADOOP_HOME}/
done


