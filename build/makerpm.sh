#!/bin/bash

set -ex

cd `dirname $0`

export JAVA_HOME=/usr/lib64/java/jdk1.6.0_25 
make -C ../src clean all
make -C ../mlx clean all

cp ../src/.libs/libhadoopUda.so .
cp ../mlx/uda.jar .
cp ../scripts/set_hadoop_slave_property.sh .

cp uda.jar libhadoopUda.so README LICENSE.txt set_hadoop_slave_property.sh ~/rpmbuild/SOURCES/
rpmbuild -ba uda.spec
cd -
