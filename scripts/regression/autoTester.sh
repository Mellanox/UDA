#!/bin/bash

export SEC=7 # Safe Exit Code - using when need to exit without considering it as error
export CEC=6  # Continue Exit Code - using when need to skip the exiting-script and continue running
export EEC1=10 # Error Exit Code 1
export EEC2=11 # Error Exit Code 2
export SLEEPING_FOR_READING=5 # time to sleep that the user will see the printed message
export WINDOES_DIR_PREFIX="\\mtrlabfs01"
export CURRENT_DATE=`date +"%Y-%m-%d_%H.%M.%S"`
echoPrefix=$(basename $0)

errorHandler ()
{	
	# there is a scenario that error occured but the return value will be 0 - 
	# when start_hadoopExcel.sh or mkteragenExcel.sh prints their usage-print,
	# (which it a unsuccessfull scenario for this script's purposes).
	# in such case this script won't recognized the problem
	phaseError=1
	if (($1 == $SEC));then
		exit 0
	elif (($1 == $EEC1)) || (($1 == $EEC2)); then
	    echo "$echoPrefix: exiting during the $2 phase"
			# in any case
		INPUT_FLAG=0
		CONTROL_FLAG=0
		CONFIGURE_FLAG=0
		SETUP_FLAG=0
		EXECUTE_FLAG=0
		VIEW_FLAG=0
		ANALIZE_FLAG=0
		EXIT_FLAG=0
		# COLLECT_FLAG and DISTRIBUTE)FLAG are not changed
		
		if (($1 == $EEC1));then
			export REPORT_SUBJECT="Daily regression runtime failure"
			export REPORT_MESSAGE="<html><body> `cat $ERROR_LOG` </body></html>"
		fi
		
		case $2 in
			prepare		) 
				COLLECT_FLAG=0
				if (($1 == $EEC1));then
					export REPORT_SUBJECT="Daily regression runtime failure"
					export REPORT_MESSAGE="<html><body> during $2 phase: error creating $TMP_DIR </body></html>"
				fi
			;;
			input		)  
				COLLECT_FLAG=0
			;;
			control		)
				COLLECT_FLAG=0
			;;
			configure	)
				COLLECT_FLAG=0
			;;
			setup		)  
				COLLECT_FLAG=0
			;;
			execute		) 
			;;
			collect		)  
				if (($1 == $EEC1));then # this lines are for double error - both in execute and collect phases
					export REPORT_SUBJECT="Daily regression runtime failure"
					export REPORT_MESSAGE="<html><body> during $2 phase: `cat $ERROR_LOG` </body></html>"
				fi
			;;
			view		) 
			;;
			analize	)
			;;
			distribute	)
			;;
		esac	
	elif (($1 != 0)) && (($1 != $CEC));then
		echo "$echoPrefix: exiting during the $2 phase according to unknown runtime error. exit code was $1"
		exit 1
    else
		phaseError=0
	fi
}

flowManager()
{
	controlVal=1
	case $1 in
		input	)  
			if (($INPUT_FLAG==0));then
				controlVal=0
			fi 
		;;
		control	)  
			if (($CONTROL_FLAG==0));then
				controlVal=0
			fi 
		;;
		configure	)  
			if (($CONFIGURE_FLAG==0));then
				controlVal=0
			fi 
		;;
		setup		)  
			if (($SETUP_FLAG==0));then
				controlVal=0
			fi 
		;;
		execute		)  
			if (($EXECUTE_FLAG==0));then
				controlVal=0
			fi
		;;
		collect		)  
			if (($COLLECT_FLAG==0));then
				controlVal=0
			fi
		;;
		view		)  
			if (($VIEW_FLAG==0));then
				controlVal=0
			fi
		;;
		analize	)  
			if (($ANALIZE_FLAG==0));then
				controlVal=0
			fi
			if [ -n "$REPORT_INPUT" ] && (($COLLECT_FLAG==0));then
				export STATISTICS_INPUT_DIR=$REPORT_INPUT
			fi
		;;
		distribute	)  
			if (($DISTRIBUTE_FLAG==0)) ;then
				controlVal=0
			fi
		;;
		"exit"		)
			if (($EXIT_FLAG==0));then
				controlVal=0
			fi
		;;
	esac
}

if [[ -z $TMP_DIR ]];then
	export TMP_DIR="/tmp/ori-temp"
fi

if [[ -z $SCRIPTS_DIR ]] && [[ -z $SVN_SCRIPTS ]];then
	echo "$echoPrefix: please export SCRIPTS_DIR or SVN_SCRIPTS "
	exit 0
	#export SCRIPTS_DIR="/labhome/oriz/scripts/commit2"
elif [[ -n $SVN_SCRIPTS ]];then
	export SCRIPTS_DIR=$TMP_DIR/scripts
	mkdir $SCRIPTS_DIR
	cd $SCRIPTS_DIR
	svn co $SVN_HADOOP/*
fi

source $SCRIPTS_DIR/defaultsMain.sh

	# prepare phase
echo "$echoPrefix: *** Prepare phase ***"
bash $SCRIPTS_DIR/prepareMain.sh
errorHandler $? "prepare"
if (($phaseError==0));then
	source $TMP_DIR/prepareExports.sh
fi

	# input phase
flowManager "input"
if (($controlVal==1));then
	echo "$echoPrefix: *** Input phase ***"
	bash $SCRIPTS_DIR/inputMain.sh $@
	errorHandler $? "input"
	if (($phaseError==0));then
		source $TMP_DIR/inputExports.sh
	fi
fi

	# control phase
flowManager "control"
if (($controlVal==1));then
	echo "$echoPrefix: *** Control phase ***"
	bash $SCRIPTS_DIR/controlMain.sh $@
	errorHandler $? "control"
	if (($phaseError==0));then
		source $TMP_DIR/controlExports.sh
	fi
fi

	# configure phase - building the configuration files and the test files
flowManager "configure"
if (($controlVal==1));then
	echo "$echoPrefix: *** Configuration phase ***"
	bash $SCRIPTS_DIR/configureMain.sh
	errorHandler $? "configure"
	if (($phaseError==0));then
		source $TMP_DIR/configureExports.sh
	fi
fi

	# setup-cluster phase
flowManager "setup"
if (($controlVal==1));then
	echo "$echoPrefix: *** Cluster-setup phase ***"
	bash $SCRIPTS_DIR/setupMain.sh
	errorHandler $? "setup"
	if (($phaseError==0));then
		source $TMP_DIR/setupExports.sh
	fi
fi

	# execution phase
flowManager "execute"
if (($controlVal==1));then
	echo "$echoPrefix: *** Execution phase ***"
	bash $SCRIPTS_DIR/executeTerasort.sh
	errorHandler $? "execute"
	if (($phaseError==0));then
		source $TMP_DIR/executeExports.sh
	fi
fi

	# data-collecting phase
flowManager "collect"
if (($controlVal==1));then
	echo "$echoPrefix: *** Data-collection phase ***"
	bash $SCRIPTS_DIR/collectMain.sh
	errorHandler $? "collect"
	if (($phaseError==0));then
		source $TMP_DIR/collectExports.sh
	fi
fi

	# view phase
flowManager "view"	
if (($controlVal==1));then
	echo "$echoPrefix: *** View phase ***"
	bash $SCRIPTS_DIR/viewTerasort.sh
	errorHandler $? "view"
	if (($phaseError==0));then
		source $TMP_DIR/viewExports.sh
	fi
fi

	# analize phase
flowManager "analize"
if (($controlVal==1));then
	echo "$echoPrefix: *** Analize phase ***"
	bash $SCRIPTS_DIR/analizeTerasort.sh
	errorHandler $? "analize"
	if (($phaseError==0));then
		source $TMP_DIR/analizeExports.sh 
	fi
fi

	# distribution phase
flowManager "distribute"
if (($controlVal==1));then
	echo "$echoPrefix: *** Result-distribution phase ***"
	bash $SCRIPTS_DIR/distributeMain.sh
	errorHandler $? "distribute"
	if (($phaseError==0));then
		source $TMP_DIR/distributeExports.sh 
	fi
fi

	# exit phase
flowManager "exit"
if (($controlVal==1));then
	echo "$echoPrefix: *** exit phase ***"
	bash $SCRIPTS_DIR/exitMain.sh
	if (($phaseError==0));then
		errorHandler $? "exit"
	fi
fi

echo "$echoPrefix: *** Finish ***"