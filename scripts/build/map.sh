#!/bin/bash

## AUGUST 2013 ##
## Map Data Stracture ##

# PUT Function
# Usage: put <map> <key> <value>
# Updates <map> and returns nothing
put() {
    if [ "$#" != 3 ]; then exit 1; fi
    mapName=$1; key=$2; value=`echo $3 | sed -e "s/ /:SP:/g"`
    eval map="\"\$$mapName\""
    map="`echo "$map" | sed -e "s/--$key=[^ ]*//g"` --$key=$value"
    eval $mapName="\"$map\""
}

# GET Function
# Usage: get <map> <key>
# Returns the matching value in an argument named "value"
# For example, you can accesss the returned value by
# echo $value
get() {
    if [ "$#" != 2 ]; then exit 1; fi
    mapName=$1; key=$2
    map=${!mapName}
    value="$(echo $map |sed -e "s/.*--${key}=\([^ ]*\).*/\1/" -e 's/:SP:/ /g' )"
}

# GET_KEYSET Function
# Usage: getKeySet <map>
# Returns all the keys in <map> in an argument named "keySet"
# For example, you can accesss the returned value by
# echo $keySet
getKeySet() {
    if [ "$#" != 1 ]; then exit 1; fi
    mapName=$1;
    eval map="\"\$$mapName\""
    keySet=`echo $map | sed -e "s/=[^ ]*//g" -e "s/\([ ]*\)--/\1/g"`
}

# PRINT_MAP Function
# Usage: printMap <map>
# Prints the the screen the entire map in the format
# --<key>=<value> --<key>=<value> --<key>=<value> ...
printMap(){
    mapName=$1
    get "${mapName}" ""
    echo $value
}
