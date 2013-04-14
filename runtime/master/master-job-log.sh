#!/bin/sh

# job that we want its logs, for example: 201304091252_0008
JOB=${1-201304091252_0008}
# where are the logs on the slaves, for example $HADOOP_HOME/logs
LOGDIR=${2-/var/logs/hadoop}
#how many lines before/after the job to copy from job/task tracker log files
CONTEXT=${3-1000}

####################  just initialization ###

#tells where are the script on the slaves
#SCRIPTSDIR=`dirname $0`
SCRIPTSDIR=/usr/lib64/uda

#tells the slaves were to scp their logs to
MASTER=`hostname`

PROG=$0
RM=/bin/rm

echo $PROG: This script will collect the following files from the LOGDIR on each slave:
echo "$PROG:  * JOB's_conf.xml and JOB's snippets from all *tracker* files"
echo "$PROG:  * JOB's folder from userlogs dir"
echo "$PROG:  * optionaly if exist: *tracker*out* files"
echo $PROG: =========
echo "$PROG: FYI - the expected usage is: $PROG JOB [LOGDIR [CONTEXT]]"
echo $PROG: =========


function quit {
	echo "$PROG: !!!! error: $1 !!!!"
	exit 1
}  

# parameters' checks and edits
[ -n "$1" ] || quit "JOB cannot be empty"
echo $JOB | grep --silent '^[0-9_]*$' || quit "job can only contains digits and underscore"
echo $LOGDIR | grep --silent '^/' || LOGDIR=`pwd`/$LOGDIR #rel-path to abs-path


################  work starts here ##########################

# ask each slave to collect its JOB logs and scp it to our /tmp
echo $PROG: running ./bin/slaves.sh, please wait...
./bin/slaves.sh $SCRIPTSDIR/job-log.sh $MASTER $JOB $LOGDIR $CONTEXT


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