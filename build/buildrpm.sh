#!/bin/bash

set -ex
BUILD_DIR=`dirname $0`
cd $BUILD_DIR/.. # Aparently, git commands (especially git archive) prefer the top level dir without path argument??

#one time setup per user
if [ ! -f ~/.rpmmacros ] ; then
	rpmdev-setuptree
fi

echo `git rev-list HEAD | wc -l` > $BUILD_DIR/gitversion.txt

# export UDA into tar, remove plugins/*/*.jar, and create tarball
echo ======== Creating source.tgz ...
rm -rf $BUILD_DIR/source.tgz
git archive --format tar  HEAD | tar --delete '*.jar' | gzip > $BUILD_DIR/source.tgz

#prepare C++
echo ======== preparing and making C++ ...
$BUILD_DIR/../src/premake.sh

#build C++ and JAVA, and then create RPM
echo ======== making RPM ...
$BUILD_DIR/makerpm.sh 
cd -
