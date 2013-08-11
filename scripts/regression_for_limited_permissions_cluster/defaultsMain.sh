#!/bin/bash

	# the default hadoop version is currently hadoop-1.1.0-patched-v2
#export DEFAULT_CSV_FILE=
#export DEFAULT_SVN_HADOOP='https://sirius.voltaire.com/repos/enterprise/uda/hadoops/hadoop-1.1.0-patched-v2'
#export DEFAULT_RPM_JAR='uda-hadoop-1.x.jar'
	# --
#export DEFAULT_RPMBUILD_DIR='rpmbuild/RPMS/x86_64'
#export DEFAULT_SVN_TRUNK='https://sirius.voltaire.com/repos/enterprise/uda/trunk'
export DEFAULT_TEST_FOLDER_DIR='/home/oriz/benchmarking/tests_files'
export DEFAULT_HADOOP_DIR='/usr/lib/gphd/hadoop-1.0.3_mlnx_gphd_1.2.0.0' #'/hadoop-1.1-patched'
#export DEFAULT_HADOOP_CLASSPATH='${HADOOP_CLASSPATH}:/usr/lib64/uda/'
export DEFAULT_DATA_SET_TYPE='cluster'
export DEFAULT_LOCAL_RESULTS_DIR='/home/oriz/benchmarking/tmp/local_results'
export DEFAULT_NFS_RESULTS_DIR='/home/oriz/benchmarking/results'
#export DEFAULT_SVN_RPM_BUILD='build/buildrpm.sh'
#export DEFAULT_SVN_REVISION=''
export DEFAULT_REPORT_MAILING_LIST='alexr,avnerb,idanwe,katyak,amirh,shania,oriz'
export DEFAULT_REPORT_SUBJECT='Terasort benchmarking results'
export DEFAULT_REPORT_COMMENT=''
export DEFAULT_RAM_SIZE=48
#export DEFAULT_JAVA_HOME='/usr/lib64/java/jdk1.6.0_25'
export DEFAULT_REPORT_INPUT=""
#export DEFAULT_CORES_DIR="/net/r-zorro004/cores"
#export DEFAULT_CORES_PATTERN="core.%p.%h.%t.%e"
export DEFAULT_HDFS_PREFIX="/user/$USER"
export DEFAULT_TERAGEN_DIR="$DEFAULT_HDFS_PREFIX/teragen/2012-10-15_08.49.56"
export DEFAULT_TERASORT_DIR="$DEFAULT_HDFS_PREFIX/terasort"
export DEFAULT_TERAVAL_DIR="$DEFAULT_HDFS_PREFIX/teraval"
