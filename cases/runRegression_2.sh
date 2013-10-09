#!/bin/bash

echo "Hello from Regression 2!"

cd /tmp/uda/scripts/regression/
su eladi -c ./expect.sh performBM_regression.sh /.autodirect/mtrswgwork/eladi/regression/csvs/cluster_conf_1.csv eladi11

echo "SUCCESS!"
