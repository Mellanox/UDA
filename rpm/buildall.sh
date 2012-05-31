#!/bin/bash

set -ex

cd `dirname $0`
UDA_DIR=`pwd`/..

#prepare C++
cd ../src
#./autogen.sh $UDA_DIR/hadoop-1.1.0-uda/
./autogen.sh $UDA_DIR/hadoop-1.0.2-uda/
autoreconf --install
./configure
cd -

#prepare JAVA
FILE=makefile.mk
cd ../mlx
#for 1.1
#echo "CBASE=$UDA_DIR/hadoop-1.1.0-uda/build/hadoop-1.1.0-SNAPSHOT/" > $FILE
#echo "CPATH=.:\$(CBASE)/hadoop-core-1.1.0-SNAPSHOT.jar:\$(CBASE)/lib/commons-logging-1.1.1.jar" >> $FILE

#for 1.0
echo "CBASE=$UDA_DIR/hadoop-1.0.2-uda/build/UDA-2.1.0-HADOOP-1.0.2/" > $FILE
echo "CPATH=.:\$(CBASE)/hadoop-core-1.0.2.jar:\$(CBASE)/lib/commons-logging-1.1.1.jar" >> $FILE
cd -

#build C++ and JAVA, and then create RPM
./makerpm.sh 