#!/bin/bash

set -ex

cd `dirname $0`

export JAVA_HOME=/usr/lib64/java/jdk1.6.0_25 
make -C ../src clean all
#make -C ../mlx-CDH3u4 clean all #works, but you have to make sure that CPATH in mlx-CDH3u4/Makefile is correct
#make -C ../mlx-0.20.2 clean all #works, but you have to make sure that CPATH in mlx-0.20.2/Makefile is correct
make -C ../mlx-1.x clean all
make -C ../mlx-3.x clean all

cp ../src/.libs/libuda.so .
cp README ./uda-CDH3u4.jar #this is TEMP till Katya fixes above make of ../mlx-CDH3u4 !!!
cp README ./uda-hadoop-0.20.2.jar #this is TEMP till Katya fixes above make of ../mlx-0.20.2 !!!
cp ../mlx-1.x/uda-hadoop-1.x.jar .
cp ../mlx-3.x/uda-hadoop-3.x.jar .
cp ../scripts/set_hadoop_slave_property.sh .

cp uda-hadoop-1.x.jar uda-hadoop-3.x.jar uda-CDH3u4.jar uda-hadoop-0.20.2.jar libuda.so README LICENSE.txt set_hadoop_slave_property.sh ~/rpmbuild/SOURCES/
rpmbuild -ba uda.spec
cd -
