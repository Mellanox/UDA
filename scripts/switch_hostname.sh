#!/bin/sh

base_h=$(hostname | sed 's/-.*//')

if [ -z ${1} ]; then
	echo "Switching host name to ${base_h}"
	hostname ${base_h}
else
	echo "Switching host name to ${base_h}-${1}"
	hostname ${base_h}-${1}
fi

