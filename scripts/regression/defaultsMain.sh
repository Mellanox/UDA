#!/bin/bash
	
export DEFAULT_CSV_FILE='/labhome/oriz/docs/blank.csv' #this value can't be empty - otherwise statiscits.sh will fail
#export DEFAULT_SCRIPTS_DIR=$SCRIPTS_DIR
export DEFAULT_TEST_FOLDER_DIR='/labhome/oriz/execsDir'
export DEFAULT_HADOOP_DIR='/hadoop-1.0.1' #'/hadoop-1.1-patched'
export DEFAULT_RPM_JAR="uda-hadoop-0.20.2.jar"
export DEFAULT_HADOOP_CLASSPATH='${HADOOP_CLASSPATH}:/usr/lib64/uda/' #uda-hadoop-1.x.jar'
#export DEFAULT_LOG_DIR='/.autodirect/mtrswgwork/oriz/regressions/'
export DEFAULT_DATA_SET_TYPE='node'
export DEFAULT_LOCAL_RESULTS_DIR='/data2/regression.collect'
export DEFAULT_NFS_RESULTS_DIR='/.autodirect/mtrswgwork/UDA/regressions-results'
#'/.autodirect/mtrswgwork/oriz/smoke'
export DEFAULT_SVN_HADOOP='https://sirius.voltaire.com/repos/enterprise/uda/hadoops/hadoop-1.1.0-patched-v2'
export DEFAULT_SVN_TRUNK='https://sirius.voltaire.com/repos/enterprise/uda/trunk'
export DEFAULT_SVN_RPM_BUILD='/build/buildrpm.sh'
export DEFAULT_SVN_REVISION=''
export DEFAULT_TEST_RUN=""
export DEFAULT_REPORT_MAILING_LIST='oriz,alexr,avnerb,idanwe,katyak,amirh,shania'
export DEFAULT_REPORT_SUBJECT='UDA Daily Regression Run Status'
export DEFAULT_REPORT_COMMENT=''
export DEFAULT_RAM_SIZE=48
export DEFAULT_JAVA_HOME='/usr/lib64/java/jdk1.6.0_25'
export DEFAULT_TMP_DIR="/tmp/ori-temp"
export DEFAULT_REPORT_INPUT=""
#export DEFAULT_UDA_CORES_DIR="MY_HADOOP_HOME"
#export DEFAULT_CORES_COLLECT_DIR="/data2/regression.cores"
export DEFAULT_CORES_DIR="/net/r-zorro004/cores"
export DEFAULT_CORES_PATTERN="core.%p.%h.%t.%e"
