#!/bin/sh

echoPrefix=`basename $0`
machines="$1"
tmpfile=~/DELETE_ME

if [[ -z "$machines" ]];then
	#machines=`echo r-sw-fatty0{1,2,3,4,5,6,7}`
	if [[ -z "$machines" ]];then
		echo "$echoPrefix: please add a default value"
		exit
	fi
fi
if [[ -z $SCRIPTS_DIR ]];then
	SCRIPTS_DIR=`pwd`
	echo "$echoPrefix: no SCRIPTS_DIR is defined, using working directory - $SCRIPTS_DIR"
fi

for machine in $machines;do
	sudo service cloudera-scm-agent stop
done
sudo service cloudera-scm-server stop
sudo rm -rf /var/run/cloudera-scm-server.pid

for machine in $machines;
do
	#ssh $machine "ps -ef | grep -i cloud | grep -v \"grep -i cloud\" | awk '{print \$2}'" > $tmpfile
	#for pid in `cat $tmpfile`;do
	#	echo "$echoPrefix: killing $pid on $machine"
		#sudo ssh $machine "ps -ef | grep $pid"
	#	sudo ssh $machine kill -9 $pid
	#done

	ssh $machine "ps -ef | grep supervisord | grep -v \"grep supervisord\" | awk '{print \$2}'" > $tmpfile
	for pid in `cat $tmpfile`;do
		echo "$echoPrefix: killing $pid on $machine"
		sudo ssh $machine "ps -ef | grep $pid"
		sudo ssh $machine bash "$SCRIPTS_DIR/killtree.sh $pid"
	done

	ssh $machine "ps -ef | grep java | grep -v \"grep java\" | head -1 | awk '{print \$3}'" > $tmpfile
	ppid=`cat $tmpfile`
	if [[ -n $ppid ]];then
		echo "$echoPrefix: killing $ppid on $machine"
		sudo ssh $machine "ps -ef | grep $pid"
		sudo ssh $machine kill -9 $ppid
	fi
	echo "$echoPrefix: sudo ssh $machine pkill -9 java"
	sudo ssh $machine pkill -9 java
done

rm $tmpfile
