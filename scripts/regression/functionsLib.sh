#!/bin/sh
echoPrefix=`eval $ECHO_PATTERN`

manageMachineHostname()
{
	local machineCleanName=$1
	local machinedesiredName=$2
	
	practicalHostname=`ssh $machineCleanName hostname`
	if [[ $practicalHostname != $machinedesiredName ]];then
		ssh $machineCleanName sudo hostname $machinedesiredName
		echo "$echoPrefix: hostname $machineCleanName changed to $machinedesiredName"		
	fi
}

commandExecuter()
{
	maxAttempt="$1"
	sleapTime="$2"
	shift 2
	cmd="$@"
	
	attempt=1

	echo "$echoPrefix: performing the command $cmd"
	eval $cmd
	status=$?

	while (($status != 0))
	do
		echo "failing executing ${cmd}. sleeping for $sleapTime seconds"
		sleep $sleapTime
		if (($attempt >= $maxAttempt));then
			exit 1
		fi
		attempt=$((attempt+1))
		
		eval $cmd
		status=$?
	done
}

funcName="$1"

shift 

case ${funcName} in
	"set_hostnames"	) manageMachineHostname $@ ;;
	"execute_command"	) commandExecuter $@ ;;
	*	)	 echo "there is no such function (function name is $funcName)"; exit $SEC;;

esac