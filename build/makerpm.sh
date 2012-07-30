#!/bin/bash

set -ex

cd `dirname $0`

export JAVA_HOME=/usr/lib64/java/jdk1.6.0_25 
make -C ../src clean all
#make -C ../mlx-CDH3u4 clean all #works, but you have to make sure that CPATH in mlx-CDH3u4/Makefile is correct
#make -C ../mlx-0.20.2 clean all #works, but you have to make sure that CPATH in mlx-0.20.2/Makefile is correct
make -C ../mlx-1.x clean all

cp ../src/.libs/libuda.so .
cp ../mlx-CDH3u4/uda-CDH3u4.jar .
cp ../mlx-0.20.2/uda-hadoop-0.20.2.jar .
cp ../mlx-1.x/uda-hadoop-1.x.jar .
cp ../scripts/set_hadoop_slave_property.sh .

cp uda-hadoop-1.x.jar libuda.so README LICENSE.txt set_hadoop_slave_property.sh ~/rpmbuild/SOURCES/
#cp uda-CDH3u4.jar uda-hadoop-0.20.2.jar uda-hadoop-1.x.jar ~/rpmbuild/SOURCES/ #in case you are building additional jars
rpmbuild -ba uda.spec
cd -
