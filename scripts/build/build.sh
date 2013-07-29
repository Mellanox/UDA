#!/bin/bash

## JUNE 2013 ##
## UDA Hadoop Build Script ##

echo -e "\n******************* Build in progress... *******************"
set -e
source ./config.sh
cd $TMP_CLONE_DIR
rm -rf $HADOOP_BRANCH_DIR $UDA_BRANCH_DIR

# Hadoop fetch phase
echo -e "\n---------- 1. Fetching Hadoop... ----------"
echo "$HADOOP_BRANCH_DIR"
mkdir "$HADOOP_BRANCH_DIR"
git clone $HADOOP_GIT_PATH $HADOOP_BRANCH_DIR
cd $HADOOP_BRANCH_DIR
git checkout $HADOOP_BRANCH
tar -xzf $HADOOP_FILENAME
cd $TMP_CLONE_DIR
echo -e "\nDone 1!"

# UDA fetch phase
echo -e "\n---------- 2. Fetching UDA... ----------"
mkdir "$UDA_BRANCH_DIR"
git clone $UDA_GIT_PATH $UDA_BRANCH_DIR
cd $UDA_BRANCH_DIR
git checkout $PATCH_BRANCH
cd $TMP_CLONE_DIR
echo -e "\nDone 2!"

# Patching hadoop
echo -e "\n---------- 3. Pathing Hadoop... ----------"
patch_file=${TMP_CLONE_DIR}/${UDA_BRANCH_DIR}/plugins/${PATCH_NAME}
PATCHED_HADOOP_DIR=${TMP_CLONE_DIR}/${HADOOP_BRANCH_DIR}/${HADOOP_DIR}
cd $PATCHED_HADOOP_DIR
patch -s -p0 < $patch_file
cd $TMP_CLONE_DIR
echo -e "\nDone 3!"

# Building hadoop
echo -e "\n---------- 4. Building the patched Hadoop... ----------"
if [ $NATIVE == "TRUE" ]; then
	BUILDPARAMS="$BUILDPARAMS -Dcompile.native=true"
fi
cd $PATCHED_HADOOP_DIR
${ANT_PATH} $BUILDPARAMS clean package
cd $TMP_CLONE_DIR
echo -e "\nDone 4!"

# Building RPM/DEB
echo -e "\n---------- 5. Building the installation file... ----------"
bash ${TMP_CLONE_DIR}/${UDA_BRANCH_DIR}/build/buildrpm.sh
if [ $BUILD_DEB_FILE == true ]; then
	echo -e "\n creating .deb file..."
	${DEB_FROM_RPM_SCRIPT_PATH}/${DEB_FROM_RPM_SCRIPT_NAME} "${TMP_CLONE_DIR}" "${DEB_FROM_RPM_SCRIPT_PATH}/debian"
fi
echo -e "\nDone 5!"
 
# Finish
touch BUILD_SUCCESSFUL
echo -e "\n******************* All DONE! *******************"

