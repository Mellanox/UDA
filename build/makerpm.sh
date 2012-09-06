#!/bin/bash

set -ex

cd `dirname $0`

export JAVA_HOME=/usr/lib64/java/jdk1.6.0_25 
make -C ../src 
make -C ../plugins/mlx-CDH3u4 clean all 
make -C ../plugins/mlx-0.20.2 clean all 
make -C ../plugins/mlx-1.x clean all
make -C ../plugins/mlx-3.x clean all

cp ../src/.libs/libuda.so .
cp ../plugins/mlx-1.x/uda-hadoop-1.x.jar .
cp ../plugins/mlx-3.x/uda-hadoop-3.x.jar .
cp ../plugins/mlx-CDH3u4/uda-CDH3u4.jar .
cp ../plugins/mlx-0.20.2/uda-hadoop-0.20.2.jar .
cp ../scripts/set_hadoop_slave_property.sh .

cp uda-hadoop-1.x.jar uda-hadoop-3.x.jar uda-CDH3u4.jar uda-hadoop-0.20.2.jar libuda.so README LICENSE.txt set_hadoop_slave_property.sh source.tgz ~/rpmbuild/SOURCES/
export revision=`cat ./svnversion.txt`
rpmbuild -ba uda.spec
echo ======= SUCCESS: Your RPM is under: ~/rpmbuild/RPMS/
cd -
