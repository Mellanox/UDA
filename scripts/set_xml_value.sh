#!/bin/bash
# Written by Idan Weinstein 
# Date: 2011-10-11


if [ $# -ne 3 ]; then
        echo "Usage: ./`basename $0` <file_name> <key> <new_value>"
	echo "replaces value under <key> of xml file <file_name> with <new_value>"
        exit 1;
fi

filename=$1
key=$2
nval=$3;

awk -v new_val=$nval -v key=$key '
BEGIN {
        FS = "[<|>]"
        keyFound=0
}

{
	if (keyFound == 1) {
                sub($3,new_val)
                keyFound=0
        }

        if ($3 == key) {
                keyFound=1
        }
        print
}


' $filename > ${filename}.new

echo "=============================="
echo "NEW values:"
echo "=============================="
cat ${filename}.new | grep -A 2 $2
echo "=============================="

echo "*** saving old file ${1}.old"
cp  ${filename} ${filename}.old
mv  ${filename}.new ${filename}
rm -rf ${filename}.new



