#!/bin/bash

echo "Hello from Regression 2!"
cd /tmp/mars_tests/UDA-uda.db/tests/scripts/regression/
su web2ver -c "bash performBM_regression.sh /.autodirect/mtrswgwork/eladi/regression/csvs/cluster_conf_2.csv"
exitStatus=$?
if (($exitStatus == 0));then
        echo "SUCCESS!"
else
        echo "FAILURE!"
fi

exit $exitStatus

