#!/bin/bash

## 11 August 2013
## =======================
## UDA Hadoop Build Script
## =======================
## This script builds all latest stored hadoops versions and patches them as needed.
## This script builds the latest UDA rpm file.
## This script builds the latest UDA deb file by converting the latest rpm file.

echo -e "\n******************* Build in progress... *******************"

# Move to temporary directory
cd $TMP_CLONE_DIR

# Hadoops fetch phase
echo -e "\n${CYAN}---------- Step 1. Fetching Hadoops... ----------${NONE}"
mkdir "$HADOOP_BRANCH_DIR"
git clone $HADOOP_GIT_PATH $HADOOP_BRANCH_DIR
echo -e "\n${GREEN}Step 1 Done!${NONE}"

# UDA fetch phase
echo -e "\n${CYAN}---------- Step 2. Fetching UDA... ----------${NONE}"
mkdir "$UDA_BRANCH_DIR"
git clone $UDA_GIT_PATH $UDA_BRANCH_DIR
echo -e "\n${GREEN}Step 2 Done!${NONE}"

# Check for changes
echo -e "\n${CYAN}---------- Step 3. Checking for latest changes... ----------${NONE}"
source ${BUILD_DIR}/changes_check.sh
if [ $CHANGED_HADOOPS == 0 ] && [ $CHANGED_UDA == 0 ]; then
	echo -e "\n${GREEN}No changes made since last build.${NONE}"
	
	# Updating the db
	echo -e "\n${PURPLE}Updating the db...${NONE}"
	rm -f ${DB_DIR}/new_latest_*
	echo -e "${PURPLE}Updated!${NONE}"

	touch BUILD_SUCCESSFUL
	echo -e "\n${GREEN}******************* All DONE! *******************${NONE}"
	exit 0
fi
cd $TMP_CLONE_DIR
echo -e "\n${GREEN}Step 3 Done!${NONE}"

# Build Changed
echo -e "\n${CYAN}---------- Step 4. Building... ----------${NONE}"
# Build Hadoops
if [ $BUILD_HADOOPS == "TRUE" ] && [ $CHANGED_HADOOPS != 0 ]; then
	echo -e "\n${YELLOW}--- Building hadoops! ---${NONE}"
	for branch in `cat ${DB_DIR}/changes_hadoops`;do

		echo -e "\n${PURPLE}--- Working on $branch... ---${NONE}"
		# Hadoops fetch phase
		cd $HADOOP_BRANCH_DIR
		git checkout $branch
		tar -xzf ${branch}.tar.gz
		cd $TMP_CLONE_DIR

		# UDA fetch phase
		cd $UDA_BRANCH_DIR
		git checkout $PATCHES_BRANCH
		cd $TMP_CLONE_DIR

		# Patching hadoop
		get "hpMap" $branch
		patch_name=${value}
		echo -e "\n${PURPLE}--- Patching $branch with $patch_name... ---${NONE}"
		patch_file=${TMP_CLONE_DIR}/${UDA_BRANCH_DIR}/plugins/${patch_name}
		PATCHED_HADOOP_DIR=${TMP_CLONE_DIR}/${HADOOP_BRANCH_DIR}/${branch}
		cd $PATCHED_HADOOP_DIR
		patch -s -p0 < $patch_file
		cd $TMP_CLONE_DIR

		# Building hadoop
		echo -e "\n${PURPLE}--- Building a patched $branch... ---${NONE}"
		if [ $NATIVE_BUILD == "TRUE" ]; then
			BUILD_PARAMS="$BUILD_PARAMS -Dcompile.native=true"
		fi
		cd $PATCHED_HADOOP_DIR
		sed -i 's/docs, //g' build.xml 	# Bug fix #
		echo -e "\nBuild in progress! If needed, see ${LOG_DIR}/${LOG_FILE}.${branch}${DELIMITER}${patch_name} for details."
		${ANT_PATH} $BUILD_PARAMS clean package > ${LOG_DIR}/${LOG_FILE}.${branch}${DELIMITER}${patch_name}
		echo -e "\n${GREEN}$branch built!${NONE}"

		# Store built patched hadoop to target directory in tar.gz form
		echo -e "\nSaving the patched hadoop as a tar.gz file in ${BUILD_TARGET_DESTINATION}..."
		tar -pczf ${BUILD_TARGET_DESTINATION}/${branch}${DELIMITER}${patch_name}.tar.gz ./build/*
		echo "Saved!"

		# Return to clone directory
		cd $TMP_CLONE_DIR

	done

	# Update latest hadoops and patches
	echo -e "\n${PURPLE}Updating the db with latest Hadoops and patches...${NONE}"
	rm -f ${DB_DIR}/latest_hadoops
	mv ${DB_DIR}/new_latest_hadoops ${DB_DIR}/latest_hadoops
	rm -f ${DB_DIR}/latest_patches
	mv ${DB_DIR}/new_latest_patches ${DB_DIR}/latest_patches
	echo -e "${PURPLE}Updated!${NONE}"

	echo -e "\n${GREEN}Finished building hadoops.${NONE}"

fi

# Build RPM/DEB
if [ $BUILD_RPM == "TRUE" ] && [ $CHANGED_UDA != 0 ]; then
	echo -e "\n${YELLOW}--- Building the .rpm file ---${NONE}"

	cd $UDA_BRANCH_DIR
        git checkout $UDA_BRANCH
	bash build/buildrpm.sh

	# Store built .rpm file to target directory
	echo -e "\nSaving the UDA .rpm file in ${BUILD_TARGET_DESTINATION}..."
	arch=`uname -m`
	rpm_filename=`ls ~/rpmbuild/RPMS/$arch/`
	mv -f ~/rpmbuild/RPMS/$arch/$rpm_filename ${BUILD_TARGET_DESTINATION}/$rpm_filename
	echo "Saved!"

	if [ $USE_BULLSEYE == "TRUE" ]; then
		echo -e "\n${YELLOW}--- Building the .rpm file with Bullseye---${NONE}"
        	echo -e "\n${PURPLE}--- Starting Bullseye... ---${NONE}"
		export COVFILE=$BULLSEYE_COV_FILE

		${BULLSEYE_DIR}/covselect --create --deleteAll --no-banner --quiet
		echo -e "\nThe Bullseye file is ${COVFILE}."
		${BULLSEYE_DIR}/cov01 --on
		${BULLSEYE_DIR}/cov01 --status

		bash build/buildrpm.sh

		# Store built .rpm file with Bullseye to target directory
		echo -e "\nSaving the UDA .rpm file with Bullseye in ${BUILD_TARGET_DESTINATION}..."
		rpm_filename_bullseye=`echo $rpm_filename | sed 's/.rpm/_bullseye.rpm/g'`
		mv -f ~/rpmbuild/RPMS/$arch/$rpm_filename ${BUILD_TARGET_DESTINATION}/$rpm_filename_bullseye
		echo "Saved!"

		echo -e "\n${PURPLE}--- Stoping Bullseye... ---${NONE}"
		${BULLSEYE_DIR}/cov01 --off
		echo -e "\nSaving the Bullseye file ${COVFILE} in ${BUILD_TARGET_DESTINATION}..."
		mv -f ${COVFILE} ${BUILD_TARGET_DESTINATION}
		echo "Saved!"
		unset COVFILE
	fi

	if [ $BUILD_DEB == "TRUE" ]; then
		echo -e "\n${YELLOW}--- Building the .deb file ---${NONE}"
		ssh -X root@$UBUNTU_SERVER 'bash -s' < ${DEB_FROM_RPM_SCRIPT_DIR}/${DEB_FROM_RPM_SCRIPT_NAME} "${BUILD_TARGET_DESTINATION}/${rpm_filename}" "${DEB_FROM_RPM_SCRIPT_DIR}/debian" "${BUILD_TARGET_DESTINATION}" "${USER}"
	fi

	# Return to clone directory
	cd $TMP_CLONE_DIR

	# Update latest uda
	echo -e "\n${PURPLE}Updating the db with latest UDA...${NONE}"
        rm -f ${DB_DIR}/latest_uda
        mv ${DB_DIR}/new_latest_uda ${DB_DIR}/latest_uda
	echo -e "${PURPLE}Updated!${NONE}"

        echo -e "\n${GREEN}Finished building uda.${NONE}"

fi

echo -e "\n${GREEN}Step 4 Done!${NONE}"

# Updating the db
echo -e "\n${PURPLE}Updating the db...${NONE}"
rm -f ${DB_DIR}/new_latest_*
echo -e "${PURPLE}Updated!${NONE}"

# Finish
touch BUILD_SUCCESSFUL
echo -e "\n${GREEN}******************* All DONE! *******************${NONE}"
echo -e "\nThe built products can be found in ${BUILD_POOL}"
tput sgr0
exit 0
