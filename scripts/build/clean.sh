#!/bin/bash

## 11 August 2013
## ============
## Clean Script
## ============
## This script cleans the running environment.

# Remove old git directories
rm -rf ${TMP_CLONE_DIR}/${HADOOP_BRANCH_DIR}
rm -rf ${TMP_CLONE_DIR}/${UDA_BRANCH_DIR}

# Remove old temporary files
rm -f ${TMP_CLONE_DIR}/BUILD_SUCCESSFUL
rm -f ${DB_DIR}/new_latest_hadoops
rm -f ${DB_DIR}/new_latest_uda
rm -f ${DB_DIR}/new_latest_patches

# Remove old builds
rm -rf ~/rpmbuild/RPMS/*

# Remove old logs
rm -rf ${LOG_DIR}

# Remove Bullseye files
if [ $USE_BULLSEYE == "TRUE" ]; then
	rm -rf /tmp/*.cov
fi

