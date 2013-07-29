#!/bin/bash

## JUNE 2013 ##
## UDA Hadoop Build Script ##

echo -e "\n******************* Build in progress... *******************"
set -e
source ./config.sh
BUILD_XML_FILE="`pwd`/build.xml" 			# Bug fix #
cd $TMP_CLONE_DIR
rm -rf $HADOOP_BRANCH_DIR $UDA_BRANCH_DIR $LOG_FILE

# Hadoop fetch phase
echo -e "\n---------- 1. Fetching Hadoop... ----------"
mkdir "$HADOOP_BRANCH_DIR"
git clone $HADOOP_GIT_PATH $HADOOP_BRANCH_DIR
cd $HADOOP_BRANCH_DIR
git checkout $HADOOP_BRANCH
tar -xzf $HADOOP_FILENAME
cd $TMP_CLONE_DIR
echo -e "\nDone (1 / 5)!"

# UDA fetch phase
echo -e "\n---------- 2. Fetching UDA... ----------"
mkdir "$UDA_BRANCH_DIR"
git clone $UDA_GIT_PATH $UDA_BRANCH_DIR
cd $UDA_BRANCH_DIR
git checkout $PATCH_BRANCH
cd $TMP_CLONE_DIR
echo -e "\nDone (2 / 5)!"

# Patching hadoop
echo -e "\n---------- 3. Pathing Hadoop... ----------"
patch_file=${TMP_CLONE_DIR}/${UDA_BRANCH_DIR}/plugins/${PATCH_NAME}
PATCHED_HADOOP_DIR=${TMP_CLONE_DIR}/${HADOOP_BRANCH_DIR}/${HADOOP_DIR}
cd $PATCHED_HADOOP_DIR
patch -s -p0 < $patch_file
cd $TMP_CLONE_DIR
echo -e "\nDone (3 / 5)!"

# Building hadoop
echo -e "\n---------- 4. Building the patched Hadoop... ----------"
if [ $NATIVE == "TRUE" ]; then
	BUILDPARAMS="$BUILDPARAMS -Dcompile.native=true"
fi
cd $PATCHED_HADOOP_DIR
cp -f ${BUILD_XML_FILE} ${PATCHED_HADOOP_DIR} 					# Bug fix #
echo -e "\n Build in progress! If needed, see ${LOG_FILE} for details."
${ANT_PATH} $BUILDPARAMS clean package > ${LOG_FILE}
cd $TMP_CLONE_DIR
echo -e "\nDone (4 / 5)!"

# Building RPM/DEB
echo -e "\n---------- 5. Building the installation files... ----------"
echo -e "\n--- Building the .rpm file ---"
bash ${TMP_CLONE_DIR}/${UDA_BRANCH_DIR}/build/buildrpm.sh
exit
if [ $BUILD_DEB_FILE == true ]; then
	echo -e "\n--- Building the .deb file ---"
	${DEB_FROM_RPM_SCRIPT_PATH}/${DEB_FROM_RPM_SCRIPT_NAME} "${TMP_CLONE_DIR}" "${DEB_FROM_RPM_SCRIPT_PATH}/debian"
fi
echo -e "\nDone (5 / 5)!"
 
# Finish
touch BUILD_SUCCESSFUL
echo -e "\n******************* All DONE! *******************"

