#!/bin/bash

## 11 August 2013
## ========================
## Environment check script
## ========================
## This script checks the running environment, pre-requirements and configurations
## before starting the build process.

# Checks to see if clone direcory is valid
if [ ! -e ${TMP_CLONE_DIR} ]; then
	echo -e "\n${RED}Error: The clone directory given does not exits!${NONE}\n"
	exit 1
elif [ ! -d ${TMP_CLONE_DIR} ]; then
	echo -e "\n${RED}Error: The clone directory given is not a directory!${NONE}\n"
        exit 1
fi

# Checks to see if the target directory is valid
if [ ! -e ${BUILD_TARGET_DESTINATION} ]; then
	mkdir -p ${BUILD_TARGET_DESTINATION}
elif [ ! -d ${BUILD_TARGET_DESTINATION} ]; then
	echo -e "\n${RED}Error: The target directory given is not a directory!${NONE}\n"
        exit 1
fi

# Checks to see if the build pool directory is valid
if [ ! -e ${BUILD_POOL} ]; then
	echo -e "\n${RED}Error: The build directory given does not exits!${NONE}\n"
	exit 1
elif [ ! -d ${BUILD_POOL} ]; then
	echo -e "\n${RED}Error: The build pool directory given is not a directory!${NONE}\n"
        exit 1
fi

# Check to see if the db directory and files are valid
if [ ! -e ${DB_DIR} ]; then
        echo -e "\n${RED}Error: The target directory given does not exits!${NONE}\n"
        exit 1
elif [ ! -d ${DB_DIR} ]; then
        echo -e "\n${RED}Error: The target directory given is not a directory!${NONE}\n"
        exit 1
elif [ ! -e ${DB_DIR}/latest_hadoops ] && [ ${BUILD_HADOOPS} == "TRUE" ]; then
	echo -e "\n${YELLOW}WARNING: latest hadoops info file is not found in the db directory given.${NONE}\n"
	echo -e "\n${YELLOW}WARNING: Expect all possible hadoops to be build.${NONE}\n"
	touch ${DB_DIR}/latest_hadoops
elif [ ! -e ${DB_DIR}/latest_uda ] && [ ${BUILD_RPM} == "TRUE" ]; then
        echo -e "\n${YELLOW}WARNING: latest uda info file is not found in the db directory given.${NONE}\n"
        echo -e "\n${YELLOW}WARNING: Expect the UDA .rpm file to be build even if no changes were made.${NONE}\n"
        touch ${DB_DIR}/latest_uda
elif [ ! -e ${DB_DIR}/latest_patches ] && [ ${BUILD_HADOOPS} == "TRUE" ]; then
        echo -e "\n${YELLOW}WARNING: latest patches info file is not found in the db directory given.${NONE}\n"
        echo -e "\n${YELLOW}WARNING: Expect all possible hadoops with patches mapped to be build.${NONE}\n"
        touch ${DB_DIR}/latest_patches
fi

# Checks to see if hadoops storage is valid
if [ ! -e ${HADOOP_STORAGE_PATH} ]; then
	echo -e "\n${RED}Error: hadoops storage not found!${NONE}\n"
        exit 1
elif [ ! -d ${HADOOP_STORAGE_PATH} ]; then
        echo -e "\n${RED}Error: hadoops storage given is not a directory!${NONE}\n"
        exit 1
fi

# Checks to see if uda git is valid
# Skip if it is a gerrit repository
echo ${UDA_GIT_PATH} | grep "ssh" > /dev/null 2>&1
if [ $? != 0 ] && [ ! -e ${UDA_GIT_PATH} ]; then
	echo -e "\n${RED}Error: uda git not found!${NONE}\n"
        exit 1
fi

# Checks to see if ant path is valid
if [ ! -e ${ANT_PATH} ]; then
	echo -e "\n${RED}Error: ant not found!${NONE}\n"
        exit 1
fi

# Checks to see if maven path is valid
if [ ! -e ${MAVEN_PATH} ]; then
	echo -e "\n${RED}Error: maven not found!${NONE}\n"
        exit 1
fi

# Checks to see if Bullseye path is valid
if [ ${USE_BULLSEYE} == "TRUE" ] && [ ! -e ${BULLSEYE_DIR} ]; then
        echo -e "\n${RED}Error: Bullseye not found!${NONE}\n"
        exit 1
fi

# Checks to see if JAVA path is valid
if [ ! -e ${JAVA_HOME} ]; then
	echo -e "\n${RED}Error: JAVA not found!${NONE}\n"
        exit 1
fi

# Checks to see if "deb_from_rpm" script path is valid and the ubuntu server is online
if [ $BUILD_DEB == "TRUE" ]; then

	ping -c 3 $UBUNTU_SERVER > /dev/null 2>&1
	if [ $? -ne 0 ]; then
	        echo -e "\n${RED}The ubuntu build server is offline!${NONE}"
		exit 1
	fi

	if [ ${DEB_FROM_RPM_SCRIPT_DIR} == "" ]; then
		echo -e "\n${RED}Error: The path of the .deb from .rpm conversion script is invalid!${NONE}\n"
		exit 1
	fi

	ssh -X $USER@$UBUNTU_SERVER "ls ${DEB_FROM_RPM_SCRIPT_DIR}/${DEB_FROM_RPM_SCRIPT_NAME} > /dev/null 2>&1"
	if [ $? != 0 ]; then
        	echo -e "\n${RED}Error: Can't find the .deb from .rpm conversion script in the ubuntu server!${NONE}\n"
	        exit 1
	fi

fi

# Checks to see if MLNX_OFED is installed
ofed_info | head -n 1 | grep OFED > /dev/null 2>&1
if [ $? != 0 ]; then
	echo -e "\n${RED}Error: MLNX_OFED is not installed on the machine!${NONE}\n"
        exit 1
fi

# Checks for permissions
if [ ! -x ${ANT_PATH} ] || [ ! -r ${ANT_PATH} ]; then
        echo -e "\n${RED}Error: ant permissions are not set!${NONE}\n"
        exit 1
fi

if [ ${USE_BULLSEYE} == "TRUE" ]; then
	if [ ! -x ${BULLSEYE_DIR}/cov01 ] || [ ! -r ${BULLSEYE_DIR}/cov01 ] || [ ! -x ${BULLSEYE_DIR}/covselect ] || [ ! -r ${BULLSEYE_DIR}/covselect ]; then
        	echo -e "\n${RED}Error: Bullseye permissions are not set!${NONE}\n"
	        exit 1
	fi
fi

for script in `ls ${BUILD_DIR}/*.sh`; do
	if [ ! -x ${script} ] || [ ! -r ${script} ]; then
	        echo -e "\n${RED}Error: $script permissions are not set!${NONE}\n"
        	exit 1
	fi
done


# Checks configuration
if [ $BUILD_HADOOPS == "FALSE" ] && [ $BUILD_RPM == "FALSE" ]; then
	echo -e "\n${RED}Error: You have not asked to build something.${NONE}\n"
        echo -e "\n${RED}Change either BUILD_HADOOPS or BUILD_RPM to TRUE in config.sh${NONE}\n"
        exit 1
fi

if [ $BUILD_RPM == "FALSE" ] && [ $BUILD_DEB == "TRUE" ]; then
	echo -e "\n${RED}Error: You can't build a .deb file without building a .rpm file.${NONE}\n"
        echo -e "\n${RED}Change BUILD_RPM to TRUE in config.sh${NONE}\n"
        exit 1
fi

# All checks pass
