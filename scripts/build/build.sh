#!/bin/bash

## JUNE 2013 ##
## UDA Hadoop Build Script ##

echo -e "\n******************* Build in progress... *******************"
set -e
# Configure environment parameters
source ./config.sh
# Check for needed configurations and files
source ./env_check.sh
# Clean Running Environment
bash ./clean.sh
# Move to temporary directory
cd $TMP_CLONE_DIR

# Hadoops fetch phase
echo -e "\n${CYAN}---------- 1. Fetching Hadoops... ----------${NONE}"
mkdir "$HADOOP_BRANCH_DIR"
git clone $HADOOP_GIT_PATH $HADOOP_BRANCH_DIR
echo -e "\n${GREEN}Done (1 / 4)!${NONE}"

# UDA fetch phase
echo -e "\n${CYAN}---------- 2. Fetching UDA... ----------${NONE}"
mkdir "$UDA_BRANCH_DIR"
git clone $UDA_GIT_PATH $UDA_BRANCH_DIR
echo -e "\n${GREEN}Done (2 / 4)!${NONE}"

# Check for changes
echo -e "\n${CYAN}---------- 3. Checking for latest changes... ----------${NONE}"
source ${BUILD_DIR}/changes_check.sh
if [ $CHANGED == 0 ]; then
	echo -e "\n${GREEN}No changes made since last build.${NONE}"
	touch BUILD_SUCCESSFUL
	echo -e "\n${GREEN}******************* All DONE! *******************${NONE}"
	exit 0
fi
cd $TMP_CLONE_DIR
echo -e "\n${GREEN}Done (3 / 4)!${NONE}"

# Build Changed
echo -e "\n${CYAN}---------- 4. Building... ----------${NONE}"
# Build Hadoops
if [ $BUILD_HADOOPS == "TRUE" ]; then
	echo -e "\n${YELLOW}--- Building hadoops! ---${NONE}"
	for branch in `cat ${DB_DIR}/changes_hadoops`;do

		echo -e "\n${PURPLE}--- Working on $branch... ---${NONE}"
		# Hadoops fetch phase
		cd $HADOOP_BRANCH_DIR
		git checkout $branch
		tar -xzf $HADOOP_FILENAME #####CHANGE TO $branch
		cd $TMP_CLONE_DIR

		# UDA fetch phase
		cd $UDA_BRANCH_DIR
		git checkout $PATCHS_BRANCH
		cd $TMP_CLONE_DIR

		# Patching hadoop
		echo -e "\n${PURPLE}--- Patching $branch... ---${NONE}"
		branch_map=`echo hadoop-1.1.2-vanilla | sed -e 's/-//g' | sed -e 's/\.//g'`"_PATCH"
		patch_name=${!branch_map}
		patch_file=${TMP_CLONE_DIR}/${UDA_BRANCH_DIR}/plugins/${patch_name}
		PATCHED_HADOOP_DIR=${TMP_CLONE_DIR}/${HADOOP_BRANCH_DIR}/${HADOOP_DIR}
		cd $PATCHED_HADOOP_DIR
		patch -s -p0 < $patch_file
		cd $TMP_CLONE_DIR

		# Building hadoop
		echo -e "\n${PURPLE}--- Building a patched $branch... ---${NONE}"
		if [ $NATIVE_BUILD == "TRUE" ]; then
			BUILD_PARAMS="$BUILD_PARAMS -Dcompile.native=true"
		fi
		cd $PATCHED_HADOOP_DIR
		cp -f ${BUILD_XML_FILE} ${PATCHED_HADOOP_DIR} 	# Bug fix #
		echo -e "\nBuild in progress! If needed, see ${LOG_FILE} for details."
		${ANT_PATH} $BUILD_PARAMS clean package > ${LOG_FILE}
		echo -e "\n${GREEN}$branch built!${NONE}"

		# Store built patched hadoop to target directory in tar.gz form
		echo -e "\nSaving the patched hadoop as a tar.gz file in ${BUILD_TARGET_DESTINATION}..."
		tar -pczf ${BUILD_TARGET_DESTINATION}/$branch-with-$patch_name.tar.gz ./build/*
		echo "Saved!"

		# Return to clone directory
		cd $TMP_CLONE_DIR

	done

	# Update latest hadoops
	rm -f ${DB_DIR}/latest_hadoops
	mv ${DB_DIR}/new_latest_hadoops ${DB_DIR}/latest_hadoops
	echo -e "\n${GREEN}Finished building hadoops.${NONE}"

fi

# Build RPM/DEB
if [ $BUILD_RPM == "TRUE" ]; then
	echo -e "\n${YELLOW}--- Building the .rpm file ---${NONE}"
        for branch in `cat ${DB_DIR}/changes_uda`;do

		cd $UDA_BRANCH_DIR
                git checkout $branch
		bash build/buildrpm.sh

		# Store built .rpm file to target directory
		cp -rf ~/rpmbuild/RPMS/x86_64/*.rpm ${BUILD_TARGET_DESTINATION}

		if [ $BUILD_DEB == "TRUE" ]; then
			echo -e "\n${YELLOW}--- Building the .deb file ---${NONE}"
			rpm_filename=`ls ${BUILD_TARGET_DESTINATION}/* | grep .rpm | cut -d / -f 2`
			ssh root@$UBUNTU_SERVER 'bash -s' < ${DEB_FROM_RPM_SCRIPT_PATH}/${DEB_FROM_RPM_SCRIPT_NAME} "${BUILD_TARGET_DESTINATION}/${rpm_filename}" "${DEB_FROM_RPM_SCRIPT_PATH}/debian"

			# Store built .deb file to target directory
			cp -rf /tmp/*.deb ${BUILD_TARGET_DESTINATION}

		fi

		# Return to clone directory
		cd $TMP_CLONE_DIR

	done

	# Update latest uda
        rm -f ${DB_DIR}/latest_uda
        mv ${DB_DIR}/new_latest_uda ${DB_DIR}/latest_uda
        echo -e "\n${GREEN}Finished building uda.${NONE}"

fi

echo -e "\n${GREEN}Done (4 / 4)!${NONE}"

# Finish
touch BUILD_SUCCESSFUL
echo -e "\n${GREEN}******************* All DONE! *******************${NONE}"
echo -e "\n${GREEN}The built products can be found in ${BUILD_TARGET_DESTINATION}${NONE}"
tput sgr0
exit 0
