#!/bin/bash

set -ex

cd `dirname $0`

export JAVA_HOME=/usr/lib64/java/jdk1.6.0_25 
make -C ../

tar --gzip -cvf utils.tgz ../utils/*  #temp, should move to ./buildrpm.sh

echo ========== creating RPM...

uda_version=`awk -F- '{print $1}' ../release`
uda_fix=`awk -F- '{print $2}' ../release`
revision=`awk -F: '{print $1}' gitversion.txt` # remove ':' (in case user's dir is dirty), since it is illegal in spec file

cp ../plugins/mlx*/uda*.jar ../src/.libs/libuda.so utils.tgz  README LICENSE.txt journal.txt source.tgz ~/rpmbuild/SOURCES/
rpmbuild -ba uda.spec --define "_revision $revision" --define "_uda_version $uda_version" --define "_uda_fix $uda_fix"

cd -
echo ========== SUCCESS: Your RPM is under: ~/rpmbuild/RPMS/
