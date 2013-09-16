#!/bin/bash

cmd=$1
maxAttempt=$2
sleapTime=$3

attempt=1

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

exit 0
