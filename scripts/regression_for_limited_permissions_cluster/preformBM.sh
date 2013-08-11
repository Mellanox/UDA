#!/bin/bash

export SCRIPTS_DIR="/home/oriz/benchmarking/scripts" # the dir that contains the regression-scripts
export TMP_DIR="/home/oriz/benchmarking/tmp"

bash $SCRIPTS_DIR/autoTester.sh -bseadt \
-Dreport.mailing.list=oriz

