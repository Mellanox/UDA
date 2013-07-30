#!/bin/bash

## JUNE 2013 ##
## Conf file for UDA Hadoop build script ##

# General Parameters
export TMP_CLONE_DIR="/tmp"
#if [[ -z $JAVA_HOME ]] ; then
	export JAVA_HOME=/usr/java/latest
#fi
export ANT_PATH="/usr/local/ant-1.8.2/bin/ant"
export LOG_FILE="${TMP_CLONE_DIR}/build_log.txt"
export DEB_FROM_RPM_SCRIPT_PATH="/.autodirect/mtrswgwork/katyak/uda/build"

# Hadoop Parameters
export HADOOP_BRANCH="hadoop-1.1.2-vanilla"
export HADOOP_FILENAME="hadoop-1.1.2.tar.gz"
export HADOOP_DIR=`echo ${HADOOP_FILENAME:0:12}`
export HADOOP_GIT_PATH="/.autodirect/mswg/git/accl/hadoops.git"
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
export BUILD_DEB_FILE=false;
OS=$(lsb_release -si)
if [ $OS == UBUNTU ]; then
	BUILD_DEB_FILE=true;
fi
export BUILD_XML_FILE="`pwd`/build.xml"

# Text Color Parameters
NONE='\033[00m'
RED='\033[01;31m'
GREEN='\033[01;32m'
YELLOW='\033[01;33m'
PURPLE='\033[01;35m'
CYAN='\033[01;36m'
WHITE='\033[01;37m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
