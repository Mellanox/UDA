#!/bin/bash

set -ex
cd `dirname $0`

#one time setup per user
if [ ! -f ~/.rpmmacros ] ; then
	rpmdev-setuptree
fi

echo `svnversion -n` > ./svnversion.txt

#prepare C++
echo ======== preparing and making C++ ...
./../src/premake.sh

# export UDA into source dir, remove plugins/*/*.jar, and create tarball
echo ======== Creating source.tgz ...
rm -rf source.tgz source
svn export .. source && rm source/plugins/*/*.jar && tar cfz source.tgz source/src source/plugins
rm -rf source

#build C++ and JAVA, and then create RPM
echo ======== making RPM ...
./makerpm.sh 
cd -
