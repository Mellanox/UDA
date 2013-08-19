#!/bin/bash

## JUNE 2013 ##
## Conf file for UDA-Hadoop build script ##

# Build Configuration
export BUILD_HADOOPS=TRUE
export BUILD_RPM=TRUE
export BUILD_DEB=TRUE
export BUILD_TARGET_DESTINATION=`pwd`/target
export BUILD_DIR=`pwd` 		# Do not change
export DB_DIR=${BUILD_DIR}/db 	# Do not change

# Hadoop->Patch Map
<<<<<<< HEAD
# Note: If you want to add another hadoop version, add it's patch here
# in the form of <haddop_branch_name_with_no_dots_or_dashes>_PATHCH
export hadoop10316hdp_PATCH="HADOOP-1.x.y.patch"
export hadoop112vanilla_PATCH="HADOOP-1.x.y.patch"
export hadoop120vanilla_PATCH="HADOOP-1.x.y.patch"
export hadoop200cdh421_PATCH="CDH-MR1-4.2.1-half.patch"
export hadoop205alpha_PATCH="HADOOP-2.x.y.patch"
export hadoop3_PATCH="HADOOP-3.x.y.patch"
=======
# Note: If you want to add another hadoop version, add it and it's patch
# here in the form:
# put "hpMap" "<haddop_version>" "<patch_name>"
put "hpMap" "hadoop-1.0.3.16-hdp" "HADOOP-1.x.y.patch"
put "hpMap" "hadoop-1.1.2-vanilla" "HADOOP-1.x.y.patch"
put "hpMap" "hadoop-1.2.0-vanilla" "HADOOP-1.x.y.patch"
put "hpMap" "hadoop-2.0.0-cdh4.2.1" "CDH-MR1-4.2.1-half.patch"
put "hpMap" "hadoop-2.0.5-alpha" "HADOOP-2.x.y.patch"
put "hpMap" "hadoop-3" "NONE"
>>>>>>> Updating the latest build process scripts to gerrit

# Hadoop Ignored Versions
# Note: If you want to add another hadoop version that will be ignored
# and not build, add it's name here, separated by "|".
export IGNORE_LIST='hadoop-3|hadoop-other|hadoop-4'

# General Parameters
export TMP_CLONE_DIR="/tmp"
export JAVA_HOME=/usr/java/latest
export ANT_PATH=${BUILD_DIR}/ant/bin/ant
export LOG_FILE="${TMP_CLONE_DIR}/build_log.txt"

# Hadoops Parameters
export HADOOP_GIT_PATH="/.autodirect/mswg/git/accl/hadoops.git"
export HADOOP_BRANCH_DIR="hadoops"

# UDA Parameters
export UDA_GIT_PATH="/.autodirect/mswg/git/accl/uda.git"
export UDA_BRANCH_DIR="uda"
export UDA_BRANCH="master"

# Patches Parameters
export PATCHES_BRANCH="master"

# Build Parameters
export NATIVE_BUILD=TRUE
export BUILD_PARAMS="-Djava5.home=$JAVA_HOME"
export BUILD_XML_FILE="`pwd`/build.xml"
<<<<<<< HEAD
export DEB_FROM_RPM_SCRIPT_PATH="/.autodirect/mtrswgwork/alongr/uda/build" #"${TMP_CLONE_DIR}/${UDA_BRANCH_DIR}/build"
=======
export DEB_FROM_RPM_SCRIPT_PATH="${TMP_CLONE_DIR}/${UDA_BRANCH_DIR}/build"
>>>>>>> Updating the latest build process scripts to gerrit
export DEB_FROM_RPM_SCRIPT_NAME="build-deb-from-rpm.sh"

# Servers
export MAIN_SERVER=mtlbuild-001-025
export BACKUP_SERVER=mtlbuild-001-026
export UBUNTU_SERVER=mtlbuild-001-027

# Mailing Parameters
<<<<<<< HEAD
export MAILING_LIST='alongr'
export REPORT_SUBJECT='UDA Daily Build Status'
=======
export MAILING_LIST='alongr,alongr'
export MAIL_SUBJECT='Daily_Build_Report_`date +"%d-%m-%Y"`'
>>>>>>> Updating the latest build process scripts to gerrit
export MAILING_SCRIPT_PATH=${BUILD_DIR}
export MAILING_SCRIPT_NAME="mailSender.py"

# Text Colors
<<<<<<< HEAD
NONE='\033[00m'
RED='\033[01;31m'
GREEN='\033[01;32m'
YELLOW='\033[01;33m'
PURPLE='\033[01;35m'
CYAN='\033[01;36m'
WHITE='\033[01;37m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
=======
export NONE='\033[00m'
export RED='\033[01;31m'
export GREEN='\033[01;32m'
export YELLOW='\033[01;33m'
export PURPLE='\033[01;35m'
export CYAN='\033[01;36m'
export WHITE='\033[01;37m'
export BOLD='\033[1m'
export UNDERLINE='\033[4m'
>>>>>>> Updating the latest build process scripts to gerrit
