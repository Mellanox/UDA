#!/bin/bash

sourcing()
{
	if (($phaseError==0));then
		source $1
	else
		echo "$echoPrefix: skiping on sourcing $1"
	fi
}

errorHandler ()
{	
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
		COLLECT_FLAG=0
		ANALIZE_FLAG=0
		VIEW_FLAG=0
		EXIT_FLAG=0
		# COLLECT_FLAG and DISTRIBUTE)FLAG are not changed
		
		if (($1 == $EEC1));then
			export REPORT_SUBJECT="Daily regression runtime failure"
			export REPORT_MESSAGE="<html><body> `cat $ERROR_LOG` </body></html>"
		fi
		
		case $2 in
			prepare		) 
				if (($1 == $EEC1));then
					export REPORT_SUBJECT="Daily regression runtime failure"
					export REPORT_MESSAGE="<html><body> during $2 phase: error creating $TMP_DIR </body></html>"
				fi
			;;
			input		)  
			;;
			control		)
			;;
			configure	)
			;;
			setup		)  
			;;
			execute		) 
			;;
			collect		)  
				if (($1 == $EEC1));then # this lines are for double error - both in execute and collect phases
					export REPORT_SUBJECT="Daily regression runtime failure"
					export REPORT_MESSAGE="<html><body> during $2 phase: `cat $ERROR_LOG` </body></html>"
				fi
			;;
			analize	)
			;;
			view		) 
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
		analize	)  
			if (($ANALIZE_FLAG==0));then
				controlVal=0
			fi
			if [ -n "$REPORT_INPUT" ] && (($COLLECT_FLAG==0));then
				export REPORT_INPUT_DIR=$REPORT_INPUT
			fi
		;;
		view		)  
			if (($VIEW_FLAG==0));then
				controlVal=0
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

source $SCRIPTS_DIR/defaultsConf.sh
source $SCRIPTS_DIR/reportConf.sh
source $SCRIPTS_DIR/namesConf.sh

echoPrefix=$(basename $0)

if [[ -z $TMP_DIR ]];then
	echo "$echoPrefix: please export TMP_DIR"
	exit 0
fi

if [[ -z $SCRIPTS_DIR ]];then
	echo "$echoPrefix: please export SCRIPTS_DIR"
	exit 0
fi
#if [[ -z $SCRIPTS_DIR ]] && [[ -z $SVN_SCRIPTS ]];then
#	echo "$echoPrefix: please export SCRIPTS_DIR or SVN_SCRIPTS"
#	exit 0
	#export SCRIPTS_DIR="/labhome/oriz/scripts/commit2"
#elif [[ -n $SVN_SCRIPTS ]];then
#	export SCRIPTS_DIR=$TMP_DIR/scripts
#	mkdir $SCRIPTS_DIR
#	cd $SCRIPTS_DIR
#	svn co $SVN_HADOOP/*
#fi

	# prepare phase
echo "$echoPrefix: *** Prepare phase ***"
bash $SCRIPTS_DIR/prepareMain.sh
errorHandler $? "prepare"
source $TMP_DIR/prepareExports.sh

	# input phase
flowManager "input"
if (($controlVal==1));then
	echo "$echoPrefix: *** Input phase ***"
	bash $SCRIPTS_DIR/inputMain.sh $@
	errorHandler $? "input"
	source $TMP_DIR/inputExports.sh
fi

	# control phase
flowManager "control"
if (($controlVal==1));then
	echo "$echoPrefix: *** Control phase ***"
	bash $SCRIPTS_DIR/controlMain.sh
	errorHandler $? "control"
	source $TMP_DIR/controlExports.sh
fi

	# configure phase - building the configuration files and the test files
flowManager "configure"
if (($controlVal==1));then
	echo "$echoPrefix: *** Configuration phase ***"
	bash $SCRIPTS_DIR/configureMain.sh
	errorHandler $? "configure"
	sourcing $TMP_DIR/configureExports.sh
fi

export FIRST_MTT_SETUP_FLAG=1
for setupName in `ls $CONFS_DIR | grep $SETUP_DIR_PREFIX`
do
	setupConfsDir=$CONFS_DIR/$setupName
	if [ -f $setupConfsDir ];then # skip if its not a folder
		continue
	fi
	
		# setup-cluster phase
	flowManager "setup"
	if (($controlVal==1));then
		echo "$echoPrefix: *** Cluster-setup phase ***"
		bash $SCRIPTS_DIR/setupMain.sh $setupConfsDir
		errorHandler $? "setup"
		sourcing $TMP_DIR/setupExports.sh
	fi

		# execution phase
	flowManager "execute"
	if (($controlVal==1));then
		echo "$echoPrefix: *** Execution phase ***"
		bash $SCRIPTS_DIR/executeMain.sh $setupConfsDir
		errorHandler $? "execute"
		source $TMP_DIR/executeExports.sh
	fi
done

	# data-collecting phase
flowManager "collect"
if (($controlVal==1));then
	echo "$echoPrefix: *** Data-collection phase ***"
	bash $SCRIPTS_DIR/collectMain.sh
	errorHandler $? "collect"
	source $TMP_DIR/collectExports.sh
fi

	# analize phase
flowManager "analize"
if (($controlVal==1));then
	echo "$echoPrefix: *** Analize phase ***"
	bash $SCRIPTS_DIR/analizeMain.sh
	errorHandler $? "analize"
	source $TMP_DIR/analizeExports.sh
fi

	# view phase
flowManager "view"	
if (($controlVal==1));then
	echo "$echoPrefix: *** View phase ***"
	bash $SCRIPTS_DIR/viewMain.sh
	errorHandler $? "view"
	source $TMP_DIR/viewExports.sh
fi

	# distribution phase
flowManager "distribute"
if (($controlVal==1));then
	echo "$echoPrefix: *** Result-distribution phase ***"
	bash $SCRIPTS_DIR/distributeMain.sh
	errorHandler $? "distribute"
	source $TMP_DIR/distributeExports.sh 
fi

	# exit phase
flowManager "exit"
if (($controlVal==1));then
	echo "$echoPrefix: *** exit phase ***"
	bash $SCRIPTS_DIR/exitMain.sh
	errorHandler $? "exit"
fi

echo "$echoPrefix: *** Finish ***"
echo -e \\n\\n\\n\\n\\n
