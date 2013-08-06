#!/bin/bash

## JUNE 2013 ##
## Clean running environment script for UDA Hadoop Build Script ##

# Remove old git directories
rm -rf ${TMP_CLONE_DIR}/${HADOOP_BRANCH_DIR}
rm -rf ${TMP_CLONE_DIR}/${UDA_BRANCH_DIR}

# Remove old log file
rm -f ${TMP_CLONE_DIR}/${LOG_FILE}

# Remove old temporary files
rm -f ${TMP_CLONE_DIR}/BUILD_SUCCESSFUL
rm -f ${DB_DIR}/new_latest_hadoops
rm -f ${DB_DIR}/new_latest_uda
rm -f ${DB_DIR}/new_latest_patches

# Remove old builds
rm -rf ~/rpmbuild/RPMS/*
