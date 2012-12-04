#!/bin/bash

	# the default hadoop version is currently hadoop-1.1.0-patched-v2
export DEFAULT_CSV_FILE='/.autodirect/mtrswgwork/UDA/daily_regressions/configuration_files/regression-1.1.0.csv'
export DEFAULT_SVN_HADOOP='https://sirius.voltaire.com/repos/enterprise/uda/hadoops/hadoop-1.1.0-patched-v2'
export DEFAULT_GIT_HADOOPS_DIR='/.autodirect/mswg/git/accl/hadoops' #'http://webdev01:8080/git/accl/hadoops.git'
export DEFAULT_GIT_HADOOP_VERSION='hadoop-1.1.0-patched-v2' # hadoop-0.20.2-patched-v2
export DEFAULT_GIT_MASTER_DIR='/.autodirect/mswg/git/accl/uda' #'http://webdev01:8080/git/accl/uda.git'
export DEFAULT_RPM_JAR='uda-hadoop-1.x.jar'
	# --
export DEFAULT_CONF_FOLDER_DIR='/.autodirect/mtrswgwork/UDA/daily_regressions/tests_confs'
export DEFAULT_MY_HADOOP_HOME='/hadoop-1.0.1'
export DEFAULT_DATA_SET_TYPE='node'
export DEFAULT_NFS_RESULTS_DIR='/.autodirect/mtrswgwork/UDA/daily_regressions/results'
export DEFAULT_SVN_REVISION=''
export DEFAULT_REPORT_MAILING_LIST='alexr,avnerb,idanwe,katyak,amirh,shania,dinal,oriz'
export DEFAULT_REPORT_NAME='regression'
export DEFAULT_REPORT_SUBJECT='UDA Daily Regression Run Status'
export DEFAULT_REPORT_COMMENT=''
export DEFAULT_RAM_SIZE=48
export DEFAULT_REPORT_INPUT=""

	# not user defined variables
export EXECUTION_MAX_ATTEMPTS=6 
export RESTART_HADOOP_MAX_ATTEMPTS=6
export SYSCTL_PATH="/etc/sysctl.conf"
export RPMBUILD_DIR='rpmbuild/RPMS/x86_64'
export SVN_TRUNK='https://sirius.voltaire.com/repos/enterprise/uda/trunk'
export TRUNK_RPM_BUILD_RELATIVE_PATH='build/buildrpm.sh'
export MASTER_RPM_BUILD_RELATIVE_PATH='build/buildrpm.sh'
export HADOOP_CLASSPATH='${HADOOP_CLASSPATH}:/labhome/oriz/log4j/:/usr/lib64/uda/'
export RELEASE_DIR='/.autodirect/mswg/release/uda/daily'
export RELEASE_RPM_RELATIVE_DIR='rpm'
export LOCAL_RESULTS_DIR='/data2/regression.collect'
export CORES_DIR="/net/r-zorro004/cores"
export CORES_PATTERN="core.%p.%h.%t.%e"
export KERNEL_CORE_PATTERN_PROPERTY='kernel.core_pattern'
export JAVA_HOME='/usr/lib64/java/jdk1.6.0_25'
export STATUS_DIR="$TMP_DIR/status"
export CODE_COVERAGE_DIR="$TMP_DIR/code_coverage_temps"
export TERAGEN_DIR="/teragen"
export TERASORT_DIR="/terasort"
export TERAVAL_DIR="/teraval"
export TEST_DFSIO_DIR="/benchmarks/TestDFSIO"
export TEST_DFSIO_READ_DIR="$TEST_DFSIO_DIR/io_read"
export TEST_DFSIO_WRITE_DIR="$TEST_DFSIO_DIR/io_write"
export PI_NUMERIC_ERROR="0.5"
export PI_HDFS_TEMP_DIR="/user/$USER"
export PI_REAL_VALUE="3.141592654"
export COVFILE=/tmp/TEST.cov
export PATH=/labhome/shania/bullseye/bin/:$PATH




