#!/bin/bash

set -ex

#prepare C++
cd ../src
./autogen.sh /volt/avnerb/workspace/uda/hadoop-1.1.0-uda/
autoreconf --install
./configure
cd -

#prepare JAVA
FILE=makefile.mk
cd ../mlx
echo 'CBASE=/volt/avnerb/workspace/uda/hadoop-1.1.0-uda/build/hadoop-1.1.0-SNAPSHOT/' > $FILE
echo 'CPATH=.:$(CBASE)/hadoop-core-1.1.0-SNAPSHOT.jar:$(CBASE)/lib/commons-logging-1.1.1.jar' >> $FILE
cd -

#build C++ and JAVA, and then create RPM
./makerpm.sh 