#!/bin/bash

## 11 August 2013
## ========================
## Check for changes script
## ========================
## This script checks for the latest changes in the hadoops git and the uda git.
## This script decides whether we need to build new hadoops based on hadoop versions changes and patches changes.
## This script decides whether we need to build a new UDA rpm file based on UDA version changes.
## Changes are evaluated based on files stored in ${DB_DIR} which this script generates.
## Note that we assume env_check.sh run successfuly before runnnig this script.

# Get latest changes in hadoops
ls -gh -p $HADOOPS_STORAGE_PATH | grep "/" | grep -v "old" >> ${DB_DIR}/new_latest_hadoops

# Get latest changes in uda
cd $TMP_CLONE_DIR
cd $UDA_BRANCH_DIR
echo -e $UDA_BRANCH  >> ${DB_DIR}/new_latest_uda
for file in `ls -p | grep -v "scripts/"`; do
	echo -e `git log --follow $file | grep "Date" | head -n 1` \\t$file  >> ${DB_DIR}/new_latest_uda
done

# Get latest changes in patches
cd $TMP_CLONE_DIR
cd $UDA_BRANCH_DIR
cd plugins/
for patch in `ls *.patch | sort`;do
	echo -e `git log --follow $patch | grep "Date" | head -n 1` \\t/$patch  >> ${DB_DIR}/new_latest_patches
done

# Find changes and filter ignored versions
diff ${DB_DIR}/new_latest_hadoops ${DB_DIR}/latest_hadoops | grep "<" | egrep -v ${IGNORE_LIST} | tr -s ' ' | cut -d " " -f 9 | cut -d / -f 1 > ${DB_DIR}/changes_hadoops_temp
diff ${DB_DIR}/new_latest_uda ${DB_DIR}/latest_uda > /dev/null 2>&1
if [ $? != 0 ]; then
	echo $UDA_BRANCH > ${DB_DIR}/changes_uda
else
	touch ${DB_DIR}/changes_uda
fi
diff ${DB_DIR}/new_latest_patches ${DB_DIR}/latest_patches | grep "<" | tr -s ' ' | cut -d / -f 2 > ${DB_DIR}/changes_patches

#Add hadoops based on patch change
getKeySet "hpMap"
for patch in `cat ${DB_DIR}/changes_patches`; do
	for hadoop in $keySet; do
		get "hpMap" $hadoop
		if [ $value == $patch ]; then
			echo $hadoop >> ${DB_DIR}/changes_hadoops_temp
		fi
	done
done

# Add mandatory version
for hadoop in `echo $MANDATORY_LIST | sed 's/|/ /g'`; do
	echo $hadoop >> ${DB_DIR}/changes_hadoops_temp
done
# Remove duplicates, ignored versions and temp file
sort -u ${DB_DIR}/changes_hadoops_temp | egrep -v ${IGNORE_LIST} > ${DB_DIR}/changes_hadoops
rm -f ${DB_DIR}/changes_hadoops_temp

# Update changes based on configuration
if [ $BUILD_HADOOPS == "FALSE" ]; then
	touch ${DB_DIR}/changes_hadoops
fi
if [ $BUILD_RPM == "FALSE" ]; then
	rm -rf ${DB_DIR}/changes_uda
	touch ${DB_DIR}/changes_uda
fi

# Calculate number of changes
let "NUM_OF_CHANGED_HADOOPS = `wc -l ${DB_DIR}/changes_hadoops | cut -d " " -f 1`"
let "NUM_OF_CHANGED_UDA = `wc -l ${DB_DIR}/changes_uda | cut -d " " -f 1`"
export CHANGED_HADOOPS=$NUM_OF_CHANGED_HADOOPS
export CHANGED_UDA=$NUM_OF_CHANGED_UDA
