#!/bin/bash

set -ex

cd `dirname $0`/..
./autogen.sh
autoreconf --install
./configure
make clean > /dev/null
cd -
