#!/bin/bash

set -ex

#prepare C++
cd `dirname $0`
./../src/premake.sh

#build C++ and JAVA, and then create RPM
./makerpm.sh 
cd -
