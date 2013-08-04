#!/bin/bash

## JUNE 2013 ##
## Conf file for UDA-Hadoop build script ##

# Build Configuration
export BUILD_HADOOPS=TRUE
export BUILD_RPM=TRUE
export BUILD_DEB=FALSE
export BUILD_TARGET_DESTINATION=`pwd`/target
export BUILD_DIR=`pwd` 		# Do not change
export DB_DIR=${BUILD_DIR}/db 	# Do not change

# Hadoop->Patch Map
# Note: If you want to add another hadoop version, add it's patch here
# in the form of <haddop_branch_name_with_no_dots_or_dashes>_PATHCH
export hadoop10316hdp_PATCH="HADOOP-1.x.y.patch"
export hadoop112vanilla_PATCH="HADOOP-1.x.y.patch"
export hadoop120vanilla_PATCH="HADOOP-1.x.y.patch"
export hadoop200cdh421_PATCH="CDH-MR1-4.2.1-half.patch"
export hadoop205alpha_PATCH="HADOOP-2.x.y.patch"
export hadoop3_PATCH="HADOOP-3.x.y.patch"

# General Parameters
export TMP_CLONE_DIR="/tmp"
export JAVA_HOME=/usr/java/latest
export ANT_PATH="/usr/local/ant-1.8.2/bin/ant"
export LOG_FILE="${TMP_CLONE_DIR}/build_log.txt"

# Hadoops Parameters
export HADOOP_GIT_PATH="/.autodirect/mswg/git/accl/hadoops.git"
export HADOOP_BRANCH_DIR="hadoops"

# Specific Hadoop Parameters
export HADOOP_BRANCH="hadoop-1.1.2-vanilla"      ### Remove
export HADOOP_FILENAME="hadoop-1.1.2.tar.gz"	 ### Remove
export HADOOP_DIR=`echo ${HADOOP_FILENAME:0:12}` ### Remove

# UDA Parameters
export UDA_GIT_PATH="/.autodirect/mswg/git/accl/uda.git"
export UDA_BRANCH_DIR="uda"

# Patchs Parameters
export PATCHS_BRANCH="master"
export NATIVE_BUILD=TRUE

# Build Parameters
export BUILD_PARAMS="-Djava5.home=$JAVA_HOME"
export BUILD_XML_FILE="`pwd`/build.xml"
export DEB_FROM_RPM_SCRIPT_PATH="${TMP_CLONE_DIR}/${UDA_BRANCH_DIR}/build/"
export DEB_FROM_RPM_SCRIPT_NAME="build-deb-from-rpm.sh"
export UBUNTU_SERVER=rswbob02

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
