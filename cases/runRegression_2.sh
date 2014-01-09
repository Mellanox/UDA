#!/bin/bash

echo "Hello from Regression 2!"
cd /tmp/mars_tests/UDA-uda.db/uda_tests/scripts/regression/
su web2ver -c "export DAILY_REGRESSION_PREFIX='daily_mars_'; bash performBM_regression.sh"
exitStatus=$?
if (($exitStatus == 0));then
        echo "SUCCESS!"
else
        echo "FAILURE!"
fi

exit $exitStatus
