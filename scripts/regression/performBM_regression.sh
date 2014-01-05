#!/bin/bash

export SCRIPTS_DIR=`pwd`
source $SCRIPTS_DIR/defaultsConf.sh
echoPrefix=`eval $ECHO_PATTERN`	

flagsCase=$RUN_MODE # Environment variable instead of command line argument
additionalFlags=$2
setupFlags="bsetad"
testFlags="bftead"
defaultFlags="bseadz"
userFlags="bsead"

case ${flagsCase} in
	"setup"		) flags="$setupFlags" ;;
	"test"		) flags="$testFlags" ;; 
	"user"		) flags="$userFlags" ;; 
	*	     	) flags="$defaultFlags" ;;   # Default.
esac

today=`date +"%w"`
if (($today == $CODE_COVERAGE_DAY));then
	echo "$echoPrefix: RUNNING WITH BULLSEYE" 
	additionalFlags="$additionalFlags -i"
fi

flags="-"$flags
echo "$echoPrefix: control-flags are: $flags $additionalFlags" 

if [[ "$USER" == "$VERIFICATION_USER" ]]; then
        export ERROR_MAILING_LIST="$DEFAULT_ERROR_MAILING_LIST"
else
        export ERROR_MAILING_LIST="$USER"
fi

export BASE_DIR="/data1/web2ver/${RUN_MODE}"


if [[ -z "$CLUSTER_CSV" ]]; then
	export CLUSTER_CSV="/.autodirect/mtrswgwork/eladi/regression/csvs/cluster_conf_2.csv"
fi

bash $SCRIPTS_DIR/autoTester.sh $flags $additionalFlags \-Dcluster.csv="$CLUSTER_CSV"

exit_status=$?
if (($exit_status != 0)); then
	echo "$echoPrefix: ERROR: REGRESSION FAILED"
fi
exit $exit_status
