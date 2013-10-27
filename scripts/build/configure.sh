#!/bin/bash

## 11 August 2013
## ====================
## Configuration script
## ====================
## This is script parses and configures all parameters set in config.ini

# Validate .ini configuration file
if [ ! -e ${INI_FILE} ]; then
        echo -e "\n${RED}Error: The .ini configuration file does not exits!${NONE}\n"
        exit 1
fi
if [ ! -r ${INI_FILE} ]; then
        echo -e "\n${RED}Error: No read permission for .ini configuration file!${NONE}\n"
        exit 1
fi

# Parse all parameters in the first section of the .ini configuration file
for parameter in `sed -e 's/[[:space:]]*\=[[:space:]]*/=/g' -e 's/;.*$//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' -e "s/^\(.*\)=\([^\"']*\)$/\1=\"\2\"/" < $INI_FILE | sed -n -e "/^\[.*\]/,/^\s*\[/{/^[^;].*\=.*/p;}" | grep -v HADOOPS_PATCHES_MAP`; do
        eval "export $parameter"
done

# Configure mapping between hadoop versions and patches
eval `cat $INI_FILE | grep "HADOOPS_PATCHES_MAP"`
for pair in ${HADOOPS_PATCHES_MAP[*]}
do
	hadoop=`echo $pair | cut -d "|" -f 1`
	patch=`echo $pair | cut -d "|" -f 2`
	put "hpMap" "$hadoop" "$patch"
done

# Configure MAVEN path
mvn_bin=`echo $MAVEN_PATH | sed 's/\/mvn//g'`

# Export PATH
export PATH=${BULLSEYE_DIR}:$PATH:${mvn_bin}

# Configure text colors
source ./colors.sh
