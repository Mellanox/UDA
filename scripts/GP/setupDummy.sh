#!/bin/bash

echoPrefix=$(basename $0)

echo "
	#!/bin/sh
	export MY_HADOOP_HOME='$DEFAULT_HADOOP_DIR'
	export HADOOP_CONF_DIR=/etc/gphd/hadoop-1.0.3_mlnx_gphd_1.2.0.0/conf.dist
	export HADOOP_VERSION='hadoop-1.0.3_mlnx_gphd_1.2.0.0'
	export HEADLINE='$DEFAULT_REPORT_SUBJECT'
	export CURRENT_LOCAL_RESULTS_DIR='$LOCAL_RESULTS_DIR/logs_${CURRENT_DATE}'
" > $TMP_DIR/setupExports.sh
