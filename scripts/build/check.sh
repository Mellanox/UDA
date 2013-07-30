#!/bin/bash

## JUNE 2013 ##
## Env check for UDA Hadoop build script ##

# Checks to see if clone direcory is valid
if [ ! -e ${TMP_CLONE_DIR} ]; then
	echo -e "\n${RED}Error: The clone directory given does not exits!${NONE}\n"
	exit 1
elif [ ! -d ${TMP_CLONE_DIR} ]; then
	echo -e "\n${RED}Error: The clone directory given is not a directory!${NONE}\n"
        exit 1
fi

# Checks to see if hadoops git is valid
if [ ! -e ${HADOOP_GIT_PATH} ]; then
	echo -e "\n${RED}Error: hadoops git not found!${NONE}\n"
        exit 1
fi

# Checks to see if uda git is valid
if [ ! -e ${UDA_GIT_PATH} ]; then
	echo -e "\n${RED}Error: uda git not found!${NONE}\n"
        exit 1
fi

# Checks to see if ant path is valid
if [ ! -e ${ANT_PATH} ]; then
	echo -e "\n${RED}Error: ant not found!${NONE}\n"
        exit 1
fi

# Checks to see if "deb_from_rpm" script path is valid
if [ ! -e ${DEB_FROM_RPM_SCRIPT_PATH} ] || [ ! -d ${DEB_FROM_RPM_SCRIPT_PATH} ]; then
	echo -e "\n${RED}Error: The path of the .deb from .rpm conversion script is invalid!${NONE}\n"
	exit 1
fi
 
# Checks to see if modified build.xml is valid
if [ ! -e ${BUILD_XML_FILE} ]; then
	echo -e "\n${RED}Error: modified build.xml file not found!${NONE}\n"
        exit 1
fi

# Checks to see if MLNX_OFED is installed
ofed_info | head -n 1 | grep OFED > /dev/null 2>&1
if [ $? != 0 ]; then
	echo -e "\n${RED}Error: MLNX_OFED is not installed on the machine!${NONE}\n"
        exit 1
fi

# All checks pass
