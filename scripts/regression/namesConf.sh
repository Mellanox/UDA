#!/bin/sh

	# terasort
export EXEC_DIR_PREFIX="exec_"
export TEST_DIR_PREFIX="test_"
export SETUP_DIR_PREFIX="setup_"
export TEST_RUN_DIR_PREFIX="testRun_"
export HADOOP_HOME_DIR_PREFIX="hadoop-"
export SMOKE_RUN_DIR_PREFIX="smoke_"
export TEST_DFSIO_WRITE_DIR_SUFFIX="_write"
export TEST_DFSIO_READ_DIR_SUFFIX="_read"
export PI_DIR_SUFFIX="_pi"
export BACKUP_SUFFIX="_backup"
export TESTS_CONF_DIR_NAME="tests_confs" 
export CONFIGURATION_FILES_DIR_NAME="configuration_files"
export LOGS_DIR_NAME="logs"
export COVERITY_DIR_NAME="code_coverage"
export TERASORT_JOBS_DIR_NAME="terasort"
export SORT_JOBS_DIR_NAME="sort"
export TEST_DFSIO_JOBS_DIR_NAME="TestDFSIO"
export PI_JOBS_DIR_NAME="pi"
export WORDCOUNT_JOBS_DIR_NAME="wordcount"
export WORDCOUNT_TEST_HDFS_DIR_SUFFIX="_VANILLA"
export ATTEMPT_DIR_INFIX="_attempt_"
export TERASORT_DATA_TABLE_FILE_NAME="terasort2Results" # those digits are for viewTerasort.sh, so the sort will succeed
export TERASORT_STAT_TABLE_FILE_NAME="terasort1Summary"
export SORT_OUTCOME_TABLE_FILE_NAME="sortOutcome"
export SORT_SUMMARY_TABLE_FILE_NAME="sortSummary"
export PI_OUTCOME_TABLE_FILE_NAME="piOutcome"
export PI_SUMMARY_TABLE_FILE_NAME="piSummary"
export TEST_DFSIO_OUTCOME_TABLE_FILE_NAME="TestDFSIOOutcome"
export TEST_DFSIO_SUMMARY_TABLE_FILE_NAME="TestDFSIOSummary"
export WORDCOUNT_OUTCOME_TABLE_FILE_NAME="wordcountOutcome"
export WORDCOUNT_SUMMARY_TABLE_FILE_NAME="wordcountSummary"
export TOTAL_OUTCOME_TABLE_FILE_NAME="totalSummary"
export HADOOP_LOGS_RELATIVE_PATH="logs"
export RECENT_JOB_DIR_NAME="recentJob"
export ENV_DIR_PREFIX="env"
export STATUS_DIR_NAME="status" 
export TMP_DIR_NAME="temps"
export PATCHED_HADOOP_SUFFIX="_LIVE-PATCHED"
export EXPLICIT_JAR_SUFFIX="_EXP"
export CACHE_FLUSHING_DATA_DIR="/data_for_cache_flushing"
export LZO_LOCAL_RESOURCES_DIR_NAME="lzoResources"
export JOB_HISTORY_FILE_NAME="jobHistory.txt"
export TEMP_SUFFIX="_temp"
export LOGGER_NAME="log4j.properties"
export CODE_COVERAGE_ENV_LOCAL_DIR_NAME="code_coverage_machines_data"
export CODE_COVERAGE_DIR_NAME="code_coverage"
export CODE_COVERAGE_TEMPLATE_COVFILE_DIR_NAME="cov_template"
export CODE_COVERAGE_FINAL_LOCAL_DIR_NAME="results_from_all_setups"
export CODE_COVERAGE_COMMIT_DIR_NAME="for_commit"
export CODE_COVERAGE_ENV_NFS_DIR_NAME=$CODE_COVERAGE_ENV_LOCAL_DIR_NAME
export CODE_COVERAGE_FINAL_NFS_DIR_NAME=$CODE_COVERAGE_FINAL_LOCAL_DIR_NAME
export CODE_COVERAGE_FILE_SUFFIX=".cov"
export CODE_COVERAGE_TEMPLATE_COVFILE_FILE_NAME="covTemplate_"
export CODE_COVERAGE_AGGRIGATED_FILE_NAME="code_coverage_aggrigated"
export CODE_COVERAGE_SUMMARY_FILE_NAME="code_coverage_summary.txt"
export CODE_COVERAGE_COMMIT_SCRIPT_PATH="/.autodirect/mswg/utils/bin/coverage/commit_cov_files.sh"
export REPORT_INTERMEDIATE_NAME="env_intermediate_report"
export TEAM_NAME="UDA"
export PRODUCT_NAME="UDA"
export RPM_SUFFIX="rpm"
export HADOOP_ENVS_SCRIPT_NAME="hadoop-env.sh"
export YARN_ENVS_SCRIPT_NAME="yarn-env.sh"
export APPLICATION_ID_GREP_IDENTIFIER="Submitted application"
export JOB_ID_GREP_IDENTIFIER="Running job:"
export ERROR_LOG_FILE_NAME="runtime_errors_log.txt"
#export CLEAN_MACHINE_NAME_FILENAME="clean_machine_name.txt"
export ENV_EXPORTS_FILENAME="envExports.sh"
export ENV_PRE_REQ_EXPORTS_FILENAME="preReqSetuepExports.sh"
export MASTER_DIR_NAME_PREFIX="master_"
export SLAVE_DIR_NAME_PREFIX="slave_"
export DSTAT_LOCAL_FILE_NAME="dstat.csv"
export DSTAT_AGGRIGATED_FILE_NAME="dstat-cluster.csv"
export CDH_MARK="cdh"
export HDP_MARK="hdp"
export SPECIFIC_EXPORTS_SCRIPTS_PREFIX="specificExportsForHadoop_"
export BUILD_SERVER_COVFILE_NAME="UDA_master.cov"
#export TESTS_EXPORTS_FILENAME="envExports.sh"
#export TESTS_PRE_REQ_EXPORTS_FILENAME="preReqSetuepExports.sh"