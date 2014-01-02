#!/bin/bash

echo "Hello from Regression 2!"
cd /tmp/mars_tests/UDA-uda.db/tests/scripts/regression/
su eladi -c "bash performBM_regression.sh"
exitStatus=$?
if (($exitStatus == 0));then
        echo "SUCCESS!"
else
        echo "FAILURE!"
fi

exit $exitStatus

