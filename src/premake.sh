#!/bin/bash

#
# Copyright (C) 2012 Auburn University
# Copyright (C) 2012 Mellanox Technologies
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at:
#  
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, 
# either express or implied. See the License for the specific language 
# governing permissions and  limitations under the License.
#
#


set -ex

if [[ -z $JAVA_HOME ]] ; then
	export JAVA_HOME=/usr/java/latest
fi

cd `dirname $0`/
mkdir -p ./build/utils/m4/ #temp till merge with master
./autogen.sh
mkdir -p ./build/utils/m4
autoreconf --install
./configure
make clean > /dev/null
make
cd -
