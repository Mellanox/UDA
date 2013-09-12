#!/bin/bash

## 11 August 2013
## ==========================================
## UDA Hadoop Pool Directory Managment Script
## ==========================================
## This script manages the build pool by moving the latest build products into
## to there proper place, creating softlinks and deleting the temporary build
## target destination.

# Managing build pool

for product in `ls -p ${BUILD_TARGET_DESTINATION} | grep -v "/"`; do

	# Manage hadoop files
	echo $product | grep ".tar.gz" > /dev/null 2>&1
	if [ $? == 0 ]; then
		for version in ${product}; do
			# Move to proper place
			mv -f ${BUILD_TARGET_DESTINATION}/$version ${BUILD_POOL}/hadoops/
			# Create a softlink
			filename=`echo $version | sed 's/.tar.gz//g'`
			ln -fs ${BUILD_POOL}/hadoops/${version} ${BUILD_POOL}/latest_daily_${filename}
		done
		continue
	fi

	echo $product | grep ".jar" > /dev/null 2>&1
	if [ $? == 0 ]; then
		for version in ${product}; do
			# Move to proper place
			mv -f ${BUILD_TARGET_DESTINATION}/$version ${BUILD_POOL}/hadoops/
			# Create a softlink
			filename=`echo $version | sed 's/.jar//g'`
			ln -fs ${BUILD_POOL}/hadoops/${version} ${BUILD_POOL}/latest_daily_${filename}
		done
		continue
	fi

	# Manage .rpm file with Bullseye enabled
	# Important Note: This needs to be checked before .rpm without Bullseye
	echo $product | grep "_bullseye.rpm" > /dev/null 2>&1
        if [ $? == 0 ]; then
		# Archive old
		if [ -f ${BUILD_POOL}/uda/${product} ];then
			old_folder=`date +"%Y_%m_%d"`
			mkdir -p ${BUILD_POOL}/uda/${old_folder}
			mv -f ${BUILD_POOL}/uda/*_bullseye.rpm ${BUILD_POOL}/uda/${old_folder}
		fi
                # Move to proper place
                mv -f ${BUILD_TARGET_DESTINATION}/$product ${BUILD_POOL}/uda/
                # Create a softlink
                filename=`echo $product | sed 's/_bullseye.rpm//g'`
                ln -fs ${BUILD_POOL}/uda/${product} ${BUILD_POOL}/latest_daily_UDA_withBullseye_${UDA_BRANCH}_rpm
		continue
        fi

	# Manage .rpm file
	echo $product | grep ".rpm" > /dev/null 2>&1
        if [ $? == 0 ]; then
                # Archive old
                if [ -f ${BUILD_POOL}/uda/${product} ];then
                        old_folder=`date +"%Y_%m_%d"`
                        mkdir -p ${BUILD_POOL}/uda/${old_folder}
                        mv -f ${BUILD_POOL}/uda/*.rpm ${BUILD_POOL}/uda/${old_folder}
                fi
                # Move to proper place
                mv -f ${BUILD_TARGET_DESTINATION}/$product ${BUILD_POOL}/uda/
                # Create a softlink
                filename=`echo $product | sed 's/.rpm//g'`
                ln -fs ${BUILD_POOL}/uda/${product} ${BUILD_POOL}/latest_daily_UDA_${UDA_BRANCH}_rpm
		continue
        fi

	# Manage .deb file
	echo $product | grep ".deb" > /dev/null 2>&1
        if [ $? == 0 ]; then
                # Archive old
                if [ -f ${BUILD_POOL}/uda/${product} ];then
                        old_folder=`date +"%Y_%m_%d"`
                        mkdir -p ${BUILD_POOL}/uda/${old_folder}
                        mv -f ${BUILD_POOL}/uda/*.deb ${BUILD_POOL}/uda/${old_folder}
                fi
                # Move to proper place
                mv -f ${BUILD_TARGET_DESTINATION}/$product ${BUILD_POOL}/uda/
                # Create a softlink
                filename=`echo $product | sed 's/.deb//g'`
                ln -fs ${BUILD_POOL}/uda/${product} ${BUILD_POOL}/latest_daily_UDA_${UDA_BRANCH}_deb
		continue
        fi

	# Manage Bullseye file
	echo $product | grep ".cov" > /dev/null 2>&1
        if [ $? == 0 ]; then
                # Archive old
                if [ -f ${BUILD_POOL}/uda/${product} ];then
                        old_folder=`date +"%Y_%m_%d"`
                        mkdir -p ${BUILD_POOL}/uda/${old_folder}
                        mv -f ${BUILD_POOL}/uda/${product} ${BUILD_POOL}/uda/${old_folder}
                fi
                # Move to proper place
                mv -f ${BUILD_TARGET_DESTINATION}/$product ${BUILD_POOL}/uda/
                # Create a softlink
                filename=`echo $product | sed 's/.cov//g'`
                ln -fs ${BUILD_POOL}/uda/${product} ${BUILD_POOL}/latest_daily_UDA_${UDA_BRANCH}_cov
		continue
        fi
done
