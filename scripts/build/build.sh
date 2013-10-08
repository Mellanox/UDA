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
ls -p ${HADOOPS_STORAGE_PATH} | grep "/" | grep -v "old"
mkdir ${HADOOP_DIR}
echo -e "\n${GREEN}Step 1 Done!${NONE}"

# UDA fetch phase
echo -e "\n${CYAN}---------- Step 2. Fetching UDA... ----------${NONE}"
mkdir "$UDA_BRANCH_DIR"
git clone $UDA_GIT_PATH $UDA_BRANCH_DIR
if [ $? != 0 ]; then
	echo -e "\n${RED}Error: failed to fetch uda git!${NONE}\n"
        exit 1
fi
echo -e "\n${GREEN}Step 2 Done!${NONE}"

# Check for changes
echo -e "\n${CYAN}---------- Step 3. Checking for latest changes... ----------${NONE}"
source ${BUILD_DIR}/changes_check.sh
if [ $CHANGED_HADOOPS == 0 ] && [ $CHANGED_UDA == 0 ]; then
	echo -e "\n${GREEN}No changes made since last build.${NONE}"
	
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
	for version in `cat ${DB_DIR}/changes_hadoops`;do

		echo -e "\n${PURPLE}--- Working on $version... ---${NONE}"
		# Hadoops fetch phase
		rm -rf ${HADOOP_DIR}/*
		cd ${HADOOPS_STORAGE_PATH}/${version}
		if [[ "$version" == *vanilla* ]] || [[ "$version" == *hdp* ]]; then
			tar_filename=`basename *hadoop*.tar.gz .tar.gz`
		elif [[ "$version" == *cdh* ]]; then
			tar_filename=`basename *mr1*.tar.gz .tar.gz`
			if [[ ! -e $tar_filename.tar.gz ]]; then 
				tar_filename=`basename *hadoop*.tar.gz .tar.gz`
			fi
		fi

		tar -xzf ${tar_filename}.tar.gz -C ${TMP_CLONE_DIR}/${HADOOP_DIR}
		cd $TMP_CLONE_DIR

		# UDA fetch phase
		cd $UDA_BRANCH_DIR
		git checkout $PATCHES_BRANCH
		cd $TMP_CLONE_DIR

		# Patching hadoop
		get "hpMap" $version
		patch_name=${value}
		echo -e "\n${PURPLE}--- Patching $version with $patch_name... ---${NONE}"
		PATCHED_HADOOP_DIR=${TMP_CLONE_DIR}/${HADOOP_DIR}/
		# Check for nested directory
		if [ `ls $PATCHED_HADOOP_DIR | wc -l` == 1 ]; then 
			PATCHED_HADOOP_DIR=$PATCHED_HADOOP_DIR/`basename $PATCHED_HADOOP_DIR/*`
		fi
		# Execute patching if needed
		if [[ "$patch_name" != NONE ]]; then
			patch_file=${TMP_CLONE_DIR}/${UDA_BRANCH_DIR}/plugins/${patch_name}
			cd $PATCHED_HADOOP_DIR
			patch -s -p0 < $patch_file
		fi
		cd $TMP_CLONE_DIR

		# Building hadoop
		echo -e "\n${PURPLE}--- Building a patched $version... ---${NONE}"
		cd $PATCHED_HADOOP_DIR
		echo -e "\nBuild in progress! If needed, see ${LOG_DIR}/${LOG_FILE}.${version}${DELIMITER}${patch_name}.txt for details."
		# Build according to version
		if [[ "$version" == *vanilla_hadoop-1* ]]; then

			sed -i 's/docs, //g' build.xml 	# Bug fix #
			${ANT_PATH} $ANT_BUILD_PARAMS clean package > ${LOG_DIR}/${LOG_FILE}.${version}${DELIMITER}${patch_name}.txt
			echo -e "\n${GREEN}$version built!${NONE}"

			# Store built patched hadoop to target directory in tar.gz form
			echo -e "\nSaving the patched hadoop as a tar.gz file in ${BUILD_TARGET_DESTINATION}..."
			tar -pczf ${BUILD_TARGET_DESTINATION}/${version}${DELIMITER}${patch_name}.tar.gz ./build/*
			echo "Saved!"

			if [ $NATIVE_BUILD == "TRUE" ]; then
				ANT_BUILD_PARAMS="$ANT_BUILD_PARAMS -Dcompile.native=true"
				echo -e "\n${YELLOW}--- Building $version as native---${NONE}"
				# Remove old build
				rm -rf ./build/
				echo -e "\nBuild in progress! If needed, see ${LOG_DIR}/${LOG_FILE}.${version}${DELIMITER}${patch_name}_native.txt for details."
				${ANT_PATH} $ANT_BUILD_PARAMS clean package > ${LOG_DIR}/${LOG_FILE}.${version}${DELIMITER}${patch_name}_native.txt
				echo -e "\n${GREEN}$version built as native!${NONE}"

				# Store built patched native hadoop to target directory in tar.gz form
				echo -e "\nSaving the patched native hadoop as a tar.gz file in ${BUILD_TARGET_DESTINATION}..."
				tar -pczf ${BUILD_TARGET_DESTINATION}/${version}${DELIMITER}${patch_name}_native.tar.gz ./build/*
				echo "Saved!"
			fi

		elif [[ "$version" == *vanilla_hadoop-2* ]] || [[ "$version" == *vanilla_hadoop-3* ]]; then

			${MAVEN_PATH} package $MAVEN_BUILD_PARAMS > ${LOG_DIR}/${LOG_FILE}.${version}${DELIMITER}${patch_name}.txt
			echo -e "\n${GREEN}$version built!${NONE}"

			# Store built patched hadoop to target directory in tar.gz form
			echo -e "\nSaving the patched hadoop as a tar.gz file in ${BUILD_TARGET_DESTINATION}..."
			cp -f ./hadoop-dist/target/*.tar.gz ${BUILD_TARGET_DESTINATION}/${version}${DELIMITER}${patch_name}.tar.gz
			echo "Saved!"

			if [ $NATIVE_BUILD == "TRUE" ]; then
				MAVEN_BUILD_PARAMS=$MAVEN_BUILD_PARAMS -Pnative
                                echo -e "\n${YELLOW}--- Building $version as native---${NONE}"
				# Remove old build
                                rm -rf ./hadoop-dist/target/
                                echo -e "\nBuild in progress! If needed, see ${LOG_DIR}/${LOG_FILE}.${version}${DELIMITER}${patch_name}_native.txt for details."
				${MAVEN_PATH} package $MAVEN_BUILD_PARAMS > ${LOG_DIR}/${LOG_FILE}.${version}${DELIMITER}${patch_name}_native.txt
                                echo -e "\n${GREEN}$version built as native!${NONE}"

                                # Store built patched native hadoop to target directory in tar.gz form
                                echo -e "\nSaving the patched native hadoop as a tar.gz file in ${BUILD_TARGET_DESTINATION}..."
				cp -f ./hadoop-dist/target/*.tar.gz ${BUILD_TARGET_DESTINATION}/${version}${DELIMITER}${patch_name}_native.tar.gz
                                echo "Saved!"
                        fi

		elif [[ "$version" == *cdh_hadoop-2.0.0-cdh4.1.2* ]] || [[ "$version" == *cdh_hadoop-2.0.0-cdh4.2.1* ]] || [[ "$version" == *hdp_hadoop-1.0.3.16-hdp* ]]; then

			# Remove old build
                        rm -rf ./build/
                        ${ANT_PATH} jar > ${LOG_DIR}/${LOG_FILE}.${version}${DELIMITER}${patch_name}.txt
                        echo -e "\n${GREEN}$version built!${NONE}"

                        # Store the built patched hadoop jar build to target directory
                        echo -e "\nSaving the patched hadoop jar file in ${BUILD_TARGET_DESTINATION}..."
			jar_filename=`basename ./build/*core*.jar .jar`
                        cp ./build/${jar_filename}.jar ${BUILD_TARGET_DESTINATION}/${version}${DELIMITER}${patch_name}.jar
                        echo "Saved!"

		elif [[ "$version" == *cdh_hadoop-2.0.0-cdh4.4.0* ]]; then
			mv bin-mapreduce1/ share/hadoop/mapreduce1/bin
			mv share/hadoop/mapreduce1/ share/
			echo "cdh_hadoop-2.0.0-cdh4.4.0 Build: Directories moved." > ${LOG_DIR}/${LOG_FILE}.${version}${DELIMITER}${patch_name}.txt
                        echo -e "\n${GREEN}$version built!${NONE}"

			# Store built patched hadoop to target directory in tar.gz form
                        echo -e "\nSaving the patched hadoop as a tar.gz file in ${BUILD_TARGET_DESTINATION}..."
                        tar -pczf ${BUILD_TARGET_DESTINATION}/${version}.tar.gz ./*
                        echo "Saved!"

		else
			echo -e "\n${RED}$version not supported!${NONE}"
		fi

		# Return to clone directory
		cd $TMP_CLONE_DIR
	done

	# Update latest hadoops and patches
	echo -e "\n${PURPLE}Updating the db with latest Hadoops and patches...${NONE}"
	rm -f ${DB_DIR}/latest_hadoops
	mv -f ${DB_DIR}/new_latest_hadoops ${DB_DIR}/latest_hadoops
	rm -f ${DB_DIR}/latest_patches
	mv -f ${DB_DIR}/new_latest_patches ${DB_DIR}/latest_patches
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
        mv -f ${DB_DIR}/new_latest_uda ${DB_DIR}/latest_uda
	echo -e "${PURPLE}Updated!${NONE}"

        echo -e "\n${GREEN}Finished building uda.${NONE}"

fi

echo -e "\n${GREEN}Step 4 Done!${NONE}"

# Finish
touch BUILD_SUCCESSFUL
echo -e "\n${GREEN}******************* All DONE! *******************${NONE}"
echo -e "\nThe built products can be found in ${BUILD_POOL}"
tput sgr0
exit 0
