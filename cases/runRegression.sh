#!/bin/bash

echo "Hello from Regression!"

cd /tmp/uda/scripts/regression/
pdsh -w hail[3-5] sudo rm -rf /tmp/test_alon/*
su alongr -c ./performBM_regression.sh
#sudo -u alongr bash -c "./performBM_regression.sh"
#./performBM_regression.sh

echo "SUCCESS!"
