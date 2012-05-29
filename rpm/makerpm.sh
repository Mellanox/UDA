#!/bin/bash

set -ex

export JAVA_HOME=/usr/lib64/java/jdk1.6.0_25 
make -C ../src clean all
make -C ../mlx clean all

cp ../src/.libs/libhadoopUda.so .
cp ../mlx/uda.jar .

rpmbuild -bb uda.spec