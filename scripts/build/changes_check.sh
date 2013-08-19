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
cd $TMP_CLONE_DIR
cd $HADOOP_BRANCH_DIR
for branch in `git branch -r | egrep -v 'HEAD|old|master'`;do
	echo -e `git show --format="%ci" $branch | head -n 1` \\t$branch >> ${DB_DIR}/new_latest_hadoops
done

# Get latest changes in uda
cd $TMP_CLONE_DIR
cd $UDA_BRANCH_DIR
echo -e `git show --format="%ci" $UDA_BRANCH | head -n 1` \\t/$UDA_BRANCH  >> ${DB_DIR}/new_latest_uda

# Get latest changes in patches
cd $TMP_CLONE_DIR
cd $UDA_BRANCH_DIR
cd plugins/
for patch in `ls *.patch`;do
	echo -e `git log $patch | grep "Date" | tail -n 1` \\t/$patch  >> ${DB_DIR}/new_latest_patches
done

# Find changes and filter ignored versions
diff ${DB_DIR}/new_latest_hadoops ${DB_DIR}/latest_hadoops | grep "<" | egrep -v ${IGNORE_LIST} | cut -d / -f 2 > ${DB_DIR}/changes_hadoops_temp
diff ${DB_DIR}/new_latest_uda ${DB_DIR}/latest_uda | grep "<" | cut -d / -f 2 > ${DB_DIR}/changes_uda
diff ${DB_DIR}/new_latest_patches ${DB_DIR}/latest_patches | grep "<" | cut -d / -f 2 > ${DB_DIR}/changes_patches

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

# Remove duplicates and temp file
sort -u ${DB_DIR}/changes_hadoops_temp | egrep -v ${IGNORE_LIST} > ${DB_DIR}/changes_hadoops
rm -f ${DB_DIR}/changes_hadoops_temp

# Calculate number of changes
let "NUM_OF_CHANGED_HADOOPS = `wc -l ${DB_DIR}/changes_hadoops | cut -d " " -f 1`"
let "NUM_OF_CHANGED_UDA = `wc -l ${DB_DIR}/changes_uda | cut -d " " -f 1`"
export CHANGED_HADOOPS=$NUM_OF_CHANGED_HADOOPS
export CHANGED_UDA=$NUM_OF_CHANGED_UDA
