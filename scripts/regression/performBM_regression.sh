#!/bin/bash
export SCRIPTS_DIR=`pwd`
params=$1
export BASE_DIR="/data1/elad/tests"
bash $SCRIPTS_DIR/autoTester.sh -bseadz $params \
-Dcluster.csv="/.autodirect/mtrswgwork/eladi/cluster_conf.csv" -Dreport.mailing.list="eladi" 
#-Dreport.current="/.autodirect/mtrswgwork/UDA/daily_regressions/results/smoke__2013-03-06_13.08.14"

exit $?
