#!/bin/sh
#
# Copyright (C) 2012 Mellanox Technologies
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at:
#  
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, 
# either express or implied. See the License for the specific language 
# governing permissions and  limitations under the License.
#
# 
# Written by Avner BenHanoch
# Date: 2013-04-25


##################################################################################
# This script will collect the following files from the LOGDIR on each slave
# *** JOB's_conf.xml and JOB's snippets from all *tracker* files
# *** JOB's folder from userlogs dir
# *** optionaly if exist: *tracker*out* files
# =========
# FYI - the expected usage is: $PROG JOB [CONTEXT [LOGDIR]]
##################################################################################
# A note for systems without slaves file in $HADOOP_CONF_DIR
# please create a file with *unique* slave names at each line and export its path,
# for example: export HADOOP_SLAVES=/tmp/my-slaves
##################################################################################

# job that we want its logs, for example: job_201304091252_0008
JOB=$1  #for example: job_201304091252_0008}

#how many lines before/after the job to copy from job/task tracker log files
CONTEXT=${2:-1000}


# where are the logs on the slaves, for example $HADOOP_HOME/logs
LOGDIR=${3:-$HADOOP_LOG_DIR}
TMP=`ps -ef | grep jobtracker | awk 'BEGIN {RS=" "; FS="="} $1=="-Dhadoop.log.dir" {print $2}'`
LOGDIR=${LOGDIR:-$TMP}
TMP=`ps -ef | grep tasktracker | awk 'BEGIN {RS=" "; FS="="} $1=="-Dhadoop.log.dir" {print $2}'`
LOGDIR=${LOGDIR:-$TMP}
LOGDIR=${LOGDIR:-/var/logs/hadoop}

####################  just initialization ###

#tells where are the script on the slaves
SCRIPTSDIR=`dirname $0`/..

#tells the slaves were to scp their logs to
MASTER=`hostname`

#calculate HADOOP_HOME, based on jobtracker, or default value - if defined
MY_HADOOP_HOME=`ps -ef | grep jobtracker | awk 'BEGIN {RS=" "; FS="="} $1=="-Dhadoop.home.dir" {print $2}'`
HADOOP_HOME=${HADOOP_HOME:-$MY_HADOOP_HOME}

#calculate HADOOP_HOME, based on tasktracker, or previous calculated value - if exists
MY_HADOOP_HOME=`ps -ef | grep tasktracker | awk 'BEGIN {RS=" "; FS="="} $1=="-Dhadoop.home.dir" {print $2}'`
HADOOP_HOME=${HADOOP_HOME:-$MY_HADOOP_HOME}

echo $LOGDIR | grep --silent '^/' || LOGDIR=`pwd`/$LOGDIR #relative-path to absolute-path
JOB=`echo $JOB | sed 's/^job_//'` # trim job_ prefix


PROG=`basename $0`
RM=/bin/rm

echo $PROG: This script will collect the following files from the LOGDIR on each slave:
echo "$PROG:  *** JOB's_conf.xml and JOB's snippets from all *tracker* files"
echo "$PROG:  *** JOB's folder from userlogs dir"
echo "$PROG:  *** optionaly if exist: *tracker*out* files"
echo $PROG: =========
echo "$PROG: FYI - the expected usage is: $PROG JOB [CONTEXT [LOGDIR]]"
echo "$PROG: FYI - calculated ARGS are: JOB=$JOB, CONTEXT=$CONTEXT, LOGDIR=$LOGDIR"
echo "$PROG: FYI - calculated values are: MASTER=$MASTER, SCRIPTSDIR=$SCRIPTSDIR, HADOOP_HOME=$HADOOP_HOME"
echo $PROG: =========


function quit {
	echo "$PROG: !!!! error: $1 !!!!"
	exit 1
}  

# parameters' checks and edits
[ -n "$1" ] || quit "JOB cannot be empty"
echo $JOB | grep --silent '^[0-9_]*$' || quit "illegal job id"


################  work starts here ##########################

# ask each slave to collect its JOB logs and scp it to our /tmp
echo $PROG: running "$HADOOP_HOME/bin/slaves.sh $SCRIPTSDIR/slave/job-log-collector.sh $MASTER $JOB $CONTEXT $LOGDIR", please wait...
$HADOOP_HOME/bin/slaves.sh $SCRIPTSDIR/slave/job-log-collector.sh $MASTER $JOB $CONTEXT $LOGDIR
echo $PROG: running also on master...
$SCRIPTSDIR/slave/job-log-collector.sh $MASTER $JOB $CONTEXT $LOGDIR # TODO: check if can copy to itself


echo $PROG: combining logs, please wait...
TARFILE=/tmp/cluster_job_$JOB.ALL-LOGS.tar
tar  --create -f $TARFILE --files-from=/dev/null

for f in /tmp/*$JOB.all-logs.tar
do
	tar --concatenate -f $TARFILE $f
	$RM -f $f
done
gzip --force $TARFILE

echo $PROG: ==== FINISHED. YOUR LOGS ARE ALL IN: $TARFILE.gz FILE =====
exit 0


#root@r-zorro002-ib ~$ P=`jps -m | grep JobTracker | awk '{print $1}'`; echo $P
#root@r-zorro002-ib ~$ export HADOOP_SLAVES=/proc/5683/cwd/mapred_hosts_allow.txt
#root@r-zorro002-ib ~$ cat /proc/$P/cwd/mapred_hosts_allow.txt # remove duplication and remove master
