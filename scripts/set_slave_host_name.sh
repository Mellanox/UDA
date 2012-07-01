#!/bin/bash
# Written by Katya Katsenelenbogen 
# Date: 2012-06-19

if [ -z "$3" ] 
then
	echo "Usage: you must pass 
	*	desired mode(ip or hostname).
	*	the desired interface for ip, or the desired ending for hostname
			For example ib0 ip OR eth4 hostname
	* 	full path to desired xml file"
	exit 1;
fi
filename=$3
element_name="slave.host.name"
interface=$2


old_property_raw=`cat $filename | grep -A 4 $element_name `
old_property=`echo $old_property_raw | awk 'BEGIN {FS="</property>"} {print $1}'`
old_value=`echo $old_property | awk 'BEGIN {FS="value>"} {print $2}' | cut -f1 -d "<"` 


if [ $1 == "ip" ]
then
	new_value=`ifconfig $interface 2>/dev/null | grep inet | cut -f2 -d ":" | cut -f1 -d " "`
elif [ $1 == "hostname" ]
then
	new_value=`hostname`-$interface
else
		echo "mode should be 'ip' or 'hostname'. you passed $1"
		exit 1;
fi

echo "the current value for the element <$element_name> is '$old_value' and the new value is '$new_value'"


awk -v new_value=$new_value -v key=$element_name -v old_value=$old_value '
BEGIN {
        keyFound=0
		value_found=0
}
{
	if (key_found==0 && value_found==0){ #searching for "slave.host.name"
		key_found=match($0, key)
		value_found=match($0, "value")
		if (key_found!=0 && value_found)
			sub(old_value, new_value)
		else
			value_found=0
	}
	if (key_found!=0 && value_found==0) {
		value_found=match($0, "value")
		if (value_found)
			sub(old_value, new_value)
	}
	print
}
' $filename > ${filename}.new

mv  ${filename}.new ${filename}
rm -rf ${filename}.new

exit 0;