
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
	local exitStatus=$1
	local phaseName=$2
	phaseError=1
	if (($exitStatus == $SEC));then
		exit 0
	elif (($exitStatus == $EEC1)) || (($exitStatus == $EEC2)) || (($exitStatus == $EEC3)); then
	    echo "$echoPrefix: exiting during the $2 phase"
			# in any case
		PREPARE_FLAG=0
		INPUT_FLAG=0
		CONTROL_FLAG=0
		CONFIGURE_FLAG=0
		SETUP_CLUSTER_FLAG=0
		SETUP_TESTS_FLAG=0
		EXECUTE_FLAG=0
		COLLECT_FLAG=0
		ANALIZE_FLAG=0
		VIEW_FLAG=0
		EXIT_FLAG=0
		# COLLECT_FLAG and DISTRIBUTE)FLAG are not changed
		
		if (($exitStatus == $EEC1));then
			export REPORT_SUBJECT="Daily regression runtime failure"
			export REPORT_MESSAGE="$REPORT_MESSAGE <html><body> `cat $ERROR_LOG` </body></html>"
			export REPORT_MAILING_LIST="$ERROR_MAILING_LIST"
		fi
		
		case $phaseName in
			prepare		) 
				if (($exitStatus == $EEC1));then
					export REPORT_SUBJECT="Daily regression runtime failure"
					export REPORT_MESSAGE="<html><body> during $2 phase: error creating $TMP_DIR </body></html>"
					export REPORT_MAILING_LIST="$ERROR_MAILING_LIST"
				fi
			;;
			prepare-setup|prepare-cluster	)			
				if (($exitStatus == $EEC3));then
						export REPORT_SUBJECT="Daily regression runtime failure"
						export REPORT_MESSAGE="<html><body> during $2 phase: setup-preReq's error occured </body></html>"
						export REPORT_MAILING_LIST="$ERROR_MAILING_LIST"
				fi
			;;
			input		)  
			;;
			control		)
			;;
			configure-cluster|configure-tests	)
			;;
			setup-tests	)  
			;;
			setup-cluster	)  
			;;
			execute		) 
			;;
			collect		)  
				if (($exitStatus == $EEC1));then # this lines are for double error - both in execute and collect phases
					export REPORT_SUBJECT="Daily regression runtime failure"
					export REPORT_MESSAGE="<html><body> during $2 phase: `cat $ERROR_LOG` </body></html>"
					export REPORT_MAILING_LIST="$ERROR_MAILING_LIST"
				fi
			;;
			analize	)
			;;
			view		) 
			;;
			distribute	)
			;;
		esac	
		exit_status=1
		export SESSION_EXCEPTION=$exitStatus
	elif (($exitStatus == $EEC4));then
		export GOT_FAILED_JOBS=1
		phaseError=0
	elif (($exitStatus != 0)) && (($exitStatus != $CEC));then
                echo "$echoPrefix: exiting during the $2 phase according to unknown runtime error. exit code was $1"
                exit 1
    	else
		phaseError=0
	fi
}

flowManager()
{
	local phaseName=$1
	controlVal=1
	case $phaseName in
		prepare-setup|prepare-cluster	)  
			if (($PREPARE_FLAG==0));then
				controlVal=0
			fi 
		;;
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
		configure-cluster|configure-tests	)  
			if (($CONFIGURE_FLAG==0));then
				controlVal=0
			fi 
		;;
		setup-tests		)
			if (($SETUP_TESTS_FLAG==0));then
				controlVal=0
			fi 
		;;
		setup-cluster	)  
			if (($SETUP_CLUSTER_FLAG==0));then
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
		analyze|analyze-env	)  
			if (($ANALIZE_FLAG==0));then
				controlVal=0
			fi
			if [ -n "$REPORT_INPUT" ] && (($COLLECT_FLAG==0));then
				export REPORT_INPUT_DIR=$REPORT_INPUT
			fi
		;;
		view|view-env		)  
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

echoPrefix=$(basename $0)
exit_status=0
PREPARE_FLAG=1

if [[ -z $SCRIPTS_DIR ]];then
	echo "$echoPrefix: please export SCRIPTS_DIR"
	exit 1
fi

if [[ -z $BASE_DIR ]];then
	echo "$echoPrefix: please export BASE_DIR"
	exit 1
fi

source $SCRIPTS_DIR/reportConf.sh
source $SCRIPTS_DIR/namesConf.sh
source $SCRIPTS_DIR/preReqConfiguration.sh
export SOURCES_DIR=$BASE_DIR/sources

	# prepare phase
echo "$echoPrefix: *** Prepare phase ***"
bash $SCRIPTS_DIR/prepareMain.sh
errorHandler $? "prepare"
sourcing $SOURCES_DIR/prepareExports.sh

	# input phase
flowManager "input"
if (($controlVal==1));then
	echo "$echoPrefix: *** Input phase ***"
	bash $SCRIPTS_DIR/inputMain.sh $@
	errorHandler $? "input"
	sourcing $SOURCES_DIR/inputExports.sh
fi

	# control phase
flowManager "control"
if (($controlVal==1));then
	echo "$echoPrefix: *** Control phase ***"
	bash $SCRIPTS_DIR/controlMain.sh
	errorHandler $? "control"
	sourcing $SOURCES_DIR/controlExports.sh
fi

	# configure cluster phase - building the configuration files and the test files
flowManager "configure-cluster"
echo "$echoPrefix: *** Cluster-configuration phase ***"
if (($controlVal==1));then
	bash $SCRIPTS_DIR/configureClusterMain.sh
	errorHandler $? "configure-cluster"
	sourcing $SOURCES_DIR/configureClusterExports.sh
fi

for clusterEnv in $ALL_ENVS
do
		# configure phase - building the configuration files and the test files
	flowManager "configure-tests"
	if (($controlVal==1));then
		echo "$echoPrefix: *** Tests-configuration phase ***"
		bash $SCRIPTS_DIR/configureTestsMain.sh $clusterEnv
		errorHandler $? "configure-tests"
		sourcing $SOURCES_DIR/configureTestsExports.sh
	fi
done

flowManager "prepare-cluster"
if (($controlVal==1));then
	echo "$echoPrefix: *** Cluster-prepare phase ***"
	bash $SCRIPTS_DIR/prepareCluster.sh
	errorHandler $? "prepare-cluster"
	sourcing $SOURCES_DIR/prepareClusterExports.sh
fi

for clusterEnv in $ALL_ENVS
do
	echo "$echoPrefix: setting $clusterEnv"

		# prepare phase
	flowManager "prepare-setup"
	if (($controlVal==1));then
		echo "$echoPrefix: *** Prepare phase ***"
		bash $SCRIPTS_DIR/prepareSetup.sh $clusterEnv
		errorHandler $? "prepare-setup" 
		source $SOURCES_DIR/prepareSetupExports.sh
	fi
	
		# setup-cluster phase
	flowManager "setup-cluster"
	if (($controlVal==1));then
		echo "$echoPrefix: *** Cluster-setup phase ***"
		bash $SCRIPTS_DIR/setupClusterMain.sh
		errorHandler $? "setup-cluster"
		sourcing $SOURCES_DIR/setupClusterExports.sh
	fi

	for testsSetup in $ALL_TESTS_SETUPS_NAMES
	#for testsSetup in `ls $CURRENT_CONFS_DIR | grep $SETUP_DIR_PREFIX`
	do
		setupConfsDir=$TESTS_CONF_DIR/$clusterEnv/$testsSetup
		
			# setup-cluster phase
		flowManager "setup-tests"
		if (($controlVal==1));then
			echo "$echoPrefix: *** Cluster-setup phase ***"
			bash $SCRIPTS_DIR/setupTestsMain.sh $setupConfsDir
			errorHandler $? "setup-tests"
			sourcing $SOURCES_DIR/setupTestsExports.sh
		fi
		
			# execution phase
		flowManager "execute"
		if (($controlVal==1));then
			echo "$echoPrefix: *** Execution phase ***"
			bash $SCRIPTS_DIR/executeMain.sh $setupConfsDir
			errorHandler $? "execute"
			sourcing $SOURCES_DIR/executeExports.sh
		fi
	done
	
		# data-collecting phase
	flowManager "collect"
	if (($controlVal==1));then
		echo "$echoPrefix: *** Data-collection phase ***"
		bash $SCRIPTS_DIR/collectMain.sh
		errorHandler $? "collect"
		sourcing $SOURCES_DIR/collectExports.sh
	fi
	
		# analize phase
	flowManager "analyze-env"
	if (($controlVal==1));then
		echo "$echoPrefix: *** Analyze-env phase ***"
		bash $SCRIPTS_DIR/analizeEnv.sh
		errorHandler $? "analyze"
		sourcing $SOURCES_DIR/analyzeEnvExports.sh
	fi

		# view phase
	flowManager "view-env"	
	if (($controlVal==1));then
		echo "$echoPrefix: *** View-env phase ***"
		bash $SCRIPTS_DIR/viewEnv.sh
		errorHandler $? "view"
		sourcing $SOURCES_DIR/viewEnvExports.sh
	fi
done

	# analize phase
flowManager "analyze"
if (($controlVal==1));then
	echo "$echoPrefix: *** Analyze phase ***"
	bash $SCRIPTS_DIR/analizeMain.sh
	errorHandler $? "analyze"
	sourcing $SOURCES_DIR/analyzeExports.sh
fi
	
	# view phase
flowManager "view"	
if (($controlVal==1));then
	echo "$echoPrefix: *** View phase ***"
	bash $SCRIPTS_DIR/viewMain.sh
	errorHandler $? "view"
	sourcing $SOURCES_DIR/viewExports.sh
fi

	# distribution phase
flowManager "distribute"
if (($controlVal==1));then
	echo "$echoPrefix: *** Result-distribution phase ***"
	bash $SCRIPTS_DIR/distributeMain.sh
	errorHandler $? "distribute"
	sourcing $SOURCES_DIR/distributeExports.sh 
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
exit $((exit_status || GOT_FAILED_JOBS))

