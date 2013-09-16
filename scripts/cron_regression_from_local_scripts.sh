#!/bin/bash

slaves="$1"
sudo pdsh -w "$slaves" "rm -rf /tmp/*"

#export SCRIPTS_DIR="/.autodirect/mtrswgwork/oriz/gerrit_regressionScripts/uda/scripts/regression"
export SCRIPTS_DIR=`pwd`

echo -e \\n\\n

sleapTime=900
maxAttempt=60
attempt=1

day=`date +"%w"`
echo day is: $day

bullseyeFlag=""
if (($day == 4));then
	bullseyeFlag="-i"
fi

bash $SCRIPTS_DIR/functionsLib.sh "execute_command" $maxAttempt $sleapTime "bash $SCRIPTS_DIR/performBM_regression.sh $bullseyeFlag"

