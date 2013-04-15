#!/bin/sh

RM=/bin/rm


MASTER=${1-rswbob12}
JOB=${2-201304091252_0008}
LOGDIR=${3-.}
CONTEXT=${4-1000}

#TARVERBOSE=""
TARVERBOSE=" --verbose "

ENDCHAR=x # Don't use g neither t, because they end *.log and *.out
SUFFIX=.job_$JOB.snippet.$ENDCHAR

FILES="$LOGDIR/*tracker*"
SAFEFILES=$FILES[^$ENDCHAR]
OUTFILES=$FILES$SUFFIX
$RM -f $OUTFILES

SLAVEDIR=`dirname $0`
$SLAVEDIR/job-log-collector.awk JOB=$JOB CONTEXT=$CONTEXT SUFFIX=$SUFFIX $SAFEFILES

TARFILE=/tmp/`hostname`_job_$JOB.all-logs.tar
$RM -f $TARFILE*


STRIP=`echo $LOGDIR | sed s/^.//`

# 1st create an empty archive, than append all files to it - this way tar will survive even if one componenet does not exist
echo "creating: $TARFILE with all job's log files..."
tar  --create -f $TARFILE --files-from=/dev/null
tar -C $LOGDIR --dereference --transform "s,^$STRIP,`hostname`," --transform "s,.$ENDCHAR$,," --append -f $TARFILE  $LOGDIR/*$JOB* 2>&1 | grep -v "Removing leading" # takes the xml file, plus any snippet we created
#tar -C $LOGDIR --dereference --transform "s,^$STRIP,`hostname`," --append -f $TARFILE  $LOGDIR/userlogs/*$JOB* 2>&1 | grep -v "Removing leading" 
tar -C $LOGDIR --dereference --transform "s,^$STRIP,`hostname`," --append -f $TARFILE  $LOGDIR/userlogs/*$JOB* 2>&1 | grep -v "Removing leading" |  grep -v "File removed before we read it" #temp, remove noise in NFS tests
tar -C $LOGDIR --dereference --transform "s,^$STRIP,`hostname`," --append -f $TARFILE  $LOGDIR/*tracker*.out 2> /dev/null || true
tar -C $LOGDIR --dereference --transform "s,^$STRIP,`hostname`," --append -f $TARFILE  $LOGDIR/*tracker*.out*[^$ENDCHAR] 2> /dev/null || true
scp $TARFILE $MASTER:/tmp/ && echo "$TARFILE was scp'ed to $MASTER:/tmp/"
$RM -f $OUTFILES $TARFILE

#TARFLAGS="-C $LOGDIR --dereference --transform \"s,^$STRIP,`hostname`,\" $VERBOSE"
#echo TARFLAGS=$TARFLAGS

#dinal@r-zorro002 hadoop-0.20-mapreduce$ x=`ps -ef | grep java | grep tasktracker | awk '{print $2}'`
#dinal@r-zorro002 hadoop-0.20-mapreduce$ sudo ls -l /proc/$x/cwd
#lrwxrwxrwx 1 mapred mapred 0 Apr 14 16:21 /proc/29591/cwd -> /var/run/cloudera-scm-agent/process/265-mapreduce-TASKTRACKER
