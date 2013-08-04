#!/bin/bash

## JUNE 2013 ##
## Check for changes in the UDA-Hadoop gits ##

# Get latest changes
# in hadoops
cd $TMP_CLONE_DIR
cd $HADOOP_BRANCH_DIR
for branch in `git branch -r | egrep -v 'HEAD|old|master'`;do
	echo -e `git show --format="%ci" $branch | head -n 1` \\t$branch >> ${DB_DIR}/new_latest_hadoops
done
# in uda
cd $TMP_CLONE_DIR
cd $UDA_BRANCH_DIR
for branch in `git branch -r | grep master | grep -v HEAD`;do
	echo -e `git show --format="%ci" $branch | head -n 1` \\t$branch  >> ${DB_DIR}/new_latest_uda
done
# Find changes
diff ${DB_DIR}/new_latest_hadoops ${DB_DIR}/latest_hadoops | grep "<" | cut -d / -f 2 > ${DB_DIR}/changes_hadoops
diff ${DB_DIR}/new_latest_uda ${DB_DIR}/latest_uda | grep "<" | cut -d / -f 2 > ${DB_DIR}/changes_uda

###############################
#echo new_latest_hadoops
#cat ${DB_DIR}/new_latest_hadoops
#echo latest_hadoops
#cat ${DB_DIR}/latest_hadoops
#echo new_latest_uda
#cat ${DB_DIR}/new_latest_uda
#echo latest_uda
#cat ${DB_DIR}/latest_uda
#echo changes_hadoops
#cat ${DB_DIR}/changes_hadoops
#echo changes_uda
#cat ${DB_DIR}/changes_uda
##############################

let "CHANGE_HADOOPS = `wc -l ${DB_DIR}/changes_hadoops | cut -d " " -f 1`"
let "CHANGE_UDA = `wc -l ${DB_DIR}/changes_uda | cut -d " " -f 1`"
let "ret_value = $CHANGE_HADOOPS + $CHANGE_UDA"
export CHANGED=$ret_value
