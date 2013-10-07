#!/bin/bash
export SCRIPTS_DIR=`pwd`
export BASE_DIR="/tmp/tests_ori"
bash $SCRIPTS_DIR/autoTester.sh -bsead \
-Dreport.mailing.list="oriz" \
-Dcluster.csv="/labhome/oriz/docs/cluster_conf.csv"
#-Dcluster.csv="/.autodirect/mtrswgwork/UDA/daily_regressions/configuration_files/cluster_conf.csv"
