#!/bin/bash

## JUNE 2013 ##
## Environment check for UDA Hadoop build script ##

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

# Checks to see if java path is valid
if [ ! -e ${JAVA_HOME} ]; then
	echo -e "\n${RED}Error: JAVA not found!${NONE}\n"
        exit 1
fi


# Checks to see if "deb_from_rpm" script path is valid
if [ ${DEB_FROM_RPM_SCRIPT_PATH} == "" ]; then
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
if [ ! -e ~/rpmbuild ]; then
        echo -e "\n${RED}Error: The rpm build directory is missing in user home directory.${NONE}\n"
        echo -e "\n${RED}Try reinstalling MLNX_OFED from /.autodirect/mswg/release/MLNX_OFED/${NONE}\n"
        exit 1
elif [ ! -e ~/rpmbuild/SOURCES/uda-CDH3u4.jar ]; then
        echo -e "\n${RED}Error: A JAR file is missing! uda-CDH3u4.jar is not found.${NONE}\n"
        echo -e "\n${RED}Try reinstalling MLNX_OFED from /.autodirect/mswg/release/MLNX_OFED/${NONE}\n"
        exit 1	
fi

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
