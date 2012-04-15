#!/bin/bash

# Written by Katya Katsenelenbogen
# Date: 2011-11-03

cd `dirname $0` # allow running the script from other dirs

ver=`cat release | tr -d '\n'`
revision=`svnversion -n`
if [  "`echo $revision | egrep ^[[:digit:]]+$`" = ""  ]; then
	revision=`echo $revision | sed 's/\([0-9]*\).*/\1/'`d
fi

version=$ver.$revision

function build {
	cd $1
	/usr/local/ant-1.8.2/bin/ant -Djava5.home=/usr/lib64/java/jdk1.6.0_25 -Dversion=$version  package 
	ret_val=$?
	if [ $ret_val -eq 0 ]
	then
		echo "build of $1 was successful"
		cd build/UDA-$version-*
		/usr/local/ant-1.8.2/bin/ant clean > /dev/null
		ret_val=$?
		if [ $ret_val -eq 0 ]
		then
			echo "ant clean finished successfully"
		else
			echo "problem while running ant clean"
		fi

		cd ..
		tar cfz UDA-$version.tar.gz  UDA-$version-*
		ret_val=$?
		if [ $ret_val -eq 0 ]
		then
			echo "tar was created successfully"
		else
			echo "problem creating tar"
		fi
		cd ..
	else
		echo "build of $1 failed"
	fi
	cd ..
	echo "*******"
}


if test -z "$1"
then
	# if no paramters were passed to script: build all hadoops in pwd
	for f in hadoop-*;
	do
		build $f
	done
else
	#building the requsted hadoop
	build  $1
fi



