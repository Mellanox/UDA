#!/bin/bash

export TMP_DIR="/tmp/regression-1.1.0"
bash $SCRIPTS_DIR/autoTester.sh -bseadcrz \
-Dgit.hadoop.version='hadoop-1.1.0-patched-v2' \
-Dcsv='/.autodirect/mtrswgwork/UDA/daily_regressions/configuration_files/regression-1.1.0.csv' \
-Drpm.jar='uda-hadoop-1.x.jar'