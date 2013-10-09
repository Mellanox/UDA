#!/bin/bash

echo "Hello from Regression 1!"

cd /tmp/
git clone ssh://r-webdev02:29418/accl/uda && cd uda && scp -p -P 29418 r-webdev02:hooks/commit-msg .git/hooks/
cd /tmp/uda/scripts/regression/
su eladi -c "./expect.sh performBM_regression.sh /.autodirect/mtrswgwork/eladi/regression/csvs/cluster_conf_2.csv eladi11"

echo "SUCCESS!"
