#!/bin/bash
export SCRIPTS_DIR=`pwd`
export TMP_DIR="/tmp/tests_ori_TEMPS"
bash $SCRIPTS_DIR/autoTester.sh -b \
-Dgit.hadoop.version='hadoop-1.1.0-patched-v2' \
-Drpm.jar='uda-hadoop-1.x.jar'  \
-Dreport.mailing.list="oriz" \
-Dcsv="/labhome/oriz/docs/new_format-1.1.0.csv" \
-Dhadoop.home="/tmp/tests_ori/hadoop-1.1.0-patched-v2" \
-Dconf.current="/.autodirect/mtrswgwork/UDA/daily_regressions/tests_confs/confs_2013-01-01_09.10.33"
#-Dreport.current="/.autodirect/mtrswgwork/UDA/daily_regressions/results/recentJob/logs"
#-Dhadoop.home="/tmp/DDN_bug_reproduce_TEMPS/hadoop-1.0.3.16" \
#-Dhugepages.count=0

#-Drpm.current="/labhome/oriz/rpmbuild/RPMS/x86_64/libuda-3.1.0-0.514.el6.x86_64.rpm" \


#-Dreport.current="/.autodirect/mtrswgwork/UDA/daily_regressions/results/smoke_2012-12-10_19.42.12/logs"
#-Dcsv='/.autodirect/mtrswgwork/UDA/daily_regressions/configuration_files/regression-1.1.0.csv' \
export TMP_DIR="/tmp/regression-0.20.2"
#bash $SCRIPTS_DIR/autoTester.sh -bseadcrz \
-Dgit.hadoop.version='hadoop-0.20.2-patched-v2' \
-Dcsv='/.autodirect/mtrswgwork/UDA/daily_regressions/configuration_files/regression-0.20.2.csv' \
-Drpm.jar='uda-hadoop-0.20.2.jar' 


