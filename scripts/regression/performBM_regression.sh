#!/bin/bash
#export SCRIPTS_DIR=`pwd`
params=$1
export BASE_DIR="/tmp/tests_ori"
bash $SCRIPTS_DIR/autoTester.sh -bseadz $params \
-Dcluster.csv="/.autodirect/mtrswgwork/UDA/daily_regressions/configuration_files/cluster_conf.csv"
#-Dreport.mailing.list="oriz" 
#-Dreport.current="/.autodirect/mtrswgwork/UDA/daily_regressions/results/smoke__2013-03-06_13.08.14"

exit $?
