#!/bin/bash

################################
# flow-control flags managing: #
################################

	# default case - when the user disn't enter any options
if  (($CONFIGURE_FLAG==0)) && (($EXECUTE_FLAG==0)) \
	&& (($ANALIZE_FLAG==0)) && (($DISTRIBUTE_FLAG==0)) \
	&& (($SETUP_FLAG==0))
then
		CONFIGURE_FLAG=1 
		SETUP_FLAG=1
	    EXECUTE_FLAG=1 
		ANALIZE_FLAG=1 
		DISTRIBUTE_FLAG=1 
		CO_FLAG=1
		RPM_FLAG=1
		ZIP_FLAG=1
		
elif (($CONFIGURE_FLAG || $SETUP_FLAG)) \
	&& ((! $EXECUTE_FLAG && ! $ANALIZE_FLAG))
then
	VIEW_FLAG=0
	COLLECT_FLAG=0
	DISTRIBUTE_FLAG=0
elif (($EXECUTE_FLAG==0));then
	COLLECT_FLAG=0
fi

if (($COLLECT_FLAG==0));then
	EXIT_FLAG=0
fi

#########################
# another control logic #
#########################

if (($TEST_RUN_FLAG==1));then
	EXIT_FLAG=0
fi

if (($CONFIGURE_FLAG == 0)) &&  (($EXECUTE_FLAG || $SETUP_FLAG));then
	if [ -n "$CURRENT_TESTS_DIR" ];then 
		path=$CURRENT_TESTS_DIR
		echo -e "$(basename $0): the tests are taken from $path"
	else
		path=$CONF_FOLDER_DIR/`ls -t $CONF_FOLDER_DIR | grep -m 1 ""`
		echo -e "$(basename $0): Warning: using the last folder created in the tests-folders directory, which is $path\n for entering explicit directory use the parameter tests.current"
		sleep $SLEEPING_FOR_READING
	fi
fi

echo "
	#!/bin/sh
		# control flags
	export CONFIGURE_FLAG=$CONFIGURE_FLAG
	export SETUP_FLAG=$SETUP_FLAG
	export EXECUTE_FLAG=$EXECUTE_FLAG
	export COLLECT_FLAG=$COLLECT_FLAG
	export ANALIZE_FLAG=$ANALIZE_FLAG
	export VIEW_FLAG=$VIEW_FLAG	
	export DISTRIBUTE_FLAG=$DISTRIBUTE_FLAG
	export EXIT_FLAG=$EXIT_FLAG
		# another flags
	export CO_FLAG=$CO_FLAG
	export RPM_FLAG=$RPM_FLAG
	export ZIP_FLAG=$ZIP_FLAG
		# general envs
	export TESTS_PATH='$path'
" > $TMP_DIR/controlExports.sh