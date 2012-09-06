#!/bin/bash

set -ex
cd `dirname $0`

#one time setup per user's home
if [ ! -f ~/.rpmmacros ] ; then
	rpmdev-setuptree
fi

#prepare C++
echo ===== preparing C++ make ...
./../src/premake.sh

# export UDA into source dir, remove plugins/*/*.jar, and create tarball
echo ===== Creating source.tgz ...
rm -rf source.tgz source
svn export .. source && rm source/plugins/*/*.jar && tar cfz source.tgz source

#build C++ and JAVA, and then create RPM
echo ===== making RPM ...
./makerpm.sh 
cd -
