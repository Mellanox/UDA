#!/bin/bash

# Written by Idan Weinstein
# Date: 2011-05-25


if [ -z "$HADOOP_HOME" ]; then
	HADOOP_HOME=`pwd`
fi

#echo HADOOP_HOME=${HADOOP_HOME}


if [ -z "$HADOOP_CONF_DIR" ]; then
	HADOOP_CONF_DIR=${HADOOP_HOME}/conf
fi

#echo HADOOP_CONF_DIR=${HADOOP_CONF_DIR}

for s in `cat ${HADOOP_CONF_DIR}/slaves | grep -v '#'`; do
	#sudo bin/slaves.sh scp -r `hostname`:${HADOOP_CONF_DIR}/* ${HADOOP_CONF_DIR}/
	echo sudo scp -r ${HADOOP_CONF_DIR} ${s}:${HADOOP_HOME}/
	sudo scp -r ${HADOOP_CONF_DIR} ${s}:${HADOOP_HOME}/
done


