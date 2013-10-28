#!/bin/bash

export SCRIPTS_DIR=`pwd`
source $SCRIPTS_DIR/defaultsConf.sh
echoPrefix=`eval $ECHO_PATTERN`	

flagsCase=$1
additionalFlags=$2
setupFlags="bsetad"
testFlags="fbetad"
defaultFlags="bseadz"

userFlags="bsead"

case ${flagsCase} in
	"setup"		) flags="$setupFlags" ;;
	"test"		) flags="$testFlags" ;; 
	"user"		) flags="$userFlags" ;; 
	*	     	)  flags="$defaultFlags" ;;   # Default.
esac
flags="-"$flags
echo "$echoPrefix: control-flags are: $flags $additionalFlags" 

export BASE_DIR="/tmp/tests_ori_soft-mode_tests"
bash $SCRIPTS_DIR/autoTester.sh $flags $additionalFlags \
-Dcluster.csv="/.autodirect/mtrswgwork/oriz/docs/cluster_conf_2.csv" \
-Dreport.mailing.list="oriz" 

exit $?
