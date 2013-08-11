#!/bin/bash

slaves="$1"
sudo pdsh -w "$slaves" "rm -rf /tmp/*"

export SCRIPTS_DIR="/labhome/oriz/scripts/regression_dev"
#export SCRIPTS_DIR="/.autodirect/mtrswgwork/UDA/daily_regressions/scripts/"
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

bash $SCRIPTS_DIR/commandExecuter.sh "bash $SCRIPTS_DIR/performBM_regression.sh $bullseyeFlag" $maxAttempt $sleapTime


#dayModulo=`echo "scale=0; ${day}%2" | bc`
#echo dayModulo is: $dayModulo
#interface="ib0"
#if (($dayModulo==0));then
#	interface="eth4"
#fi
#if [ -n $2 ];then
#	interface=$2
#fi
#echo interface is: $interface

