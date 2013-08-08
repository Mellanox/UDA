#!/bin/bash

source ./config.sh
ping -c 3 $MAIN_SERVER > /dev/null 2>&1
if [ $? -ne 0 ]; then
	# The main server is offline
	echo -e "\n${RED}The main build server is offline!${NONE}"
	echo -e "\n${YELLOW}Building on backup server...${NONE}"
	bash ./build.sh
	exit 0
fi
echo -e "\n${GREEN}The main build server is online!${NONE}\n"
