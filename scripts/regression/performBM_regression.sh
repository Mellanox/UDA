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

if [[ "$USER" == "$VERIFICATION_USER" ]]; then
        export ERROR_MAILING_LIST="$DEFAULT_ERROR_MAILING_LIST"
else
        export ERROR_MAILING_LIST="$USER"
fi

export BASE_DIR="/data1/web2ver"

bash $SCRIPTS_DIR/autoTester.sh $flags $additionalFlags \-Dcluster.csv="/.autodirect/mtrswgwork/eladi/regression/csvs/cluster_conf_2.csv"
#\-Dreport.mailing.list="eladi" 

exit_status=$?
if (($exit_status != 0)); then
	echo "$echoPrefix: ERROR: REGRESSION FAILED"
fi
exit $exit_status
