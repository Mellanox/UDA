#!/bin/bash
# Written by Katya Katsenelenbogen 
# Date: 2012-06-19



usage() {
	echo "
usage: $0 <options>
	There are two ways to configure 'slave.host.name' property:
		1. Use a suffix to be added to hostname (such as 'eagle1-ib'). In this
			case in /etc/hosts should be an entry spesifying ip for 'eagle1-ib'.
		2. Use ip address of the interface you wish to run hadoop on.
	
	Required options:
		--hadoop-conf-dir=DIR  	path to existing hadoop installation that will use hadoop
	AND one of the following options:
		--interface=INTERFACE_NAME	interface name as it appears in 'ifconfig'
		--host-suffix=HOST_SUFFIX  	suffix to be added to hostname
  "
  exit 1
}



OPTS=$(getopt \
  -n $0 \
  -o '' \
  -l 'hadoop-conf-dir:' \
  -l 'host-suffix:' \
  -l 'interface:' \
  -- "$@")


eval set -- "$OPTS"
while true ; do
    case "$1" in
        --hadoop-conf-dir)
        HADOOP_CONF_DIR=$2 ; shift 2
        ;;
        --interface)
        INTERFACE_NAME=$2 ; shift 2
        ;;
        --host-suffix)
        HOST_SUFFIX=$2 ; shift 2
        ;;
        --)
        shift ; break
        ;;
        *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
done


if [ -z "$(eval "echo \$HADOOP_CONF_DIR")" ]; 
then
    echo Missing param: hadoop-conf-dir
    usage
fi

if [ -n "$HOST_SUFFIX" ]  
then
	new_value=`hostname`-$HOST_SUFFIX
elif [ -n "$INTERFACE_NAME" ] 
then 
	new_value=`ifconfig $interface 2>/dev/null | grep inet | cut -f2 -d ":" | cut -f1 -d " "`
else
	usage
fi

filename=$HADOOP_CONF_DIR/mapred-site.xml
element_name="slave.host.name"


old_property_raw=`cat $filename | grep -A 4 $element_name `

if [ -z "$old_property_raw" ]
then
	echo "property does not exist: adding it!"
	new_property="<property> \n<name>$element_name <\\\name> \n<value>$new_value<\\\value> \n<\\\property>"
	lala="chocholate"
	sed "/^<configuration>/a $new_property" $filename > ${filename}.new
	mv  ${filename}.new ${filename}
	rm -rf ${filename}.new
	exit 1;
fi


old_property=`echo $old_property_raw | awk 'BEGIN {FS="</property>"} {print $1}'`
old_value=`echo $old_property | awk 'BEGIN {FS="value>"} {print $2}' | cut -f1 -d "<"` 


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