#!/bin/bash

#export SCRIPTS_DIR="/labhome/oriz/scripts/commit2" # the dir that contains the regression-scripts

export TMP_DIR="/tmp/regression_temps-1.1.0"
bash $SCRIPTS_DIR/autoTester.sh -bseadcr \
-Dsvn.hadoop='https://sirius.voltaire.com/repos/enterprise/uda/hadoops/hadoop-1.1.0-patched-v2' \
-Drpm.jar='uda-hadoop-1.x.jar' \
-Dcsv='/.autodirect/mtrswgwork/UDA/daily_regressions/configuration_files/regression-1.1.0.csv'

export TMP_DIR="/tmp/regression_temps-0.20.2"
bash $SCRIPTS_DIR/autoTester.sh -bseadcr \
-Dsvn.hadoop='https://sirius.voltaire.com/repos/enterprise/uda/hadoops/hadoop-0.20.2-patched-v2' \
-Drpm.jar='uda-hadoop-0.20.2.jar' \
-Dcsv='/.autodirect/mtrswgwork/UDA/daily_regressions/configuration_files/regression-0.20.2.csv'

