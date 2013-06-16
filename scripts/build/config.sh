#!/bin/bash

# General Parameters
export TMP_CLONE_DIR="/tmp"
if [[ -z $JAVA_HOME ]] ; then
	export JAVA_HOME=/usr/java/latest
fi
export ANT_PATH=`which ant`

# Hadoop Parameters
export HADOOP_BRANCH="hadoop-1.1.2-vanilla"
export HADOOP_FILENAME="hadoop-1.1.2.tar.gz"
export HADOOP_DIR=`echo ${HADOOP_FILENAME:0:12}`
export HADOOP_GIT_PATH="/.autodirect/mswg/git/accl/hadoops"
export HADOOP_BRANCH_DIR="hadoops"

# UDA Parameters
export UDA_GIT_PATH="/.autodirect/mswg/git/accl/uda.git"
export UDA_BRANCH_DIR="uda"

# Patch Parameters
export PATCH_BRANCH="master"
export PATCH_NAME="HADOOP-1.x.y.patch"
export NATIVE=TRUE

# Build Parameters
export BUILDPARAMS="-Djava5.home=$JAVA_HOME"
