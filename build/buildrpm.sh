#!/bin/bash

set -ex

#one time setup per user's home
if [ ! -f ~/.rpmmacros ] ; then
	rpmdev-setuptree
fi

#prepare C++
cd `dirname $0`
./../src/premake.sh

#build C++ and JAVA, and then create RPM
./makerpm.sh 
cd -
