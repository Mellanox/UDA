#!/bin/bash

echoPrefix=`eval $ECHO_PATTERN`
#echo ENV_FIXED_NAME=$ENV_FIXED_NAME MASTER=$MASTER SLAVES_BY_SPACES=$SLAVES_BY_SPACES CODE_COVERAGE_FILE_SUFFIX=$CODE_COVERAGE_FILE_SUFFIX CODE_COVERAGE_FILE=$CODE_COVERAGE_FILE

if (($CODE_COVE_FLAG==1));then
#	for machine in $MASTER $SLAVES_BY_SPACES;do
#		#echo "ssh $machine scp $COVFILE $RES_SERVER:/tmp/${machine}_coverage.cov"
#		newCovfileName=${ENV_FIXED_NAME}_${machine}${CODE_COVERAGE_FILE_SUFFIX}
#		sudo chown -R $USER $CODE_COVERAGE_FINAL_DIR
#		sudo scp $machine:$CODE_COVERAGE_FILE $CODE_COVERAGE_FINAL_DIR/$newCovfileName
#	done


	sudo chmod -R $DIRS_PERMISSIONS $CODE_COVERAGE_FINAL_DIR
	finalCovfile=$CODE_COVERAGE_COMMIT_DIR/${CODE_COVERAGE_AGGRIGATED_FILE_NAME}${CODE_COVERAGE_FILE_SUFFIX}
	echo "$echoPrefix: merge command is: covmerge --create --file $finalCovfile $CODE_COVERAGE_FINAL_DIR/*"
	covmerge --create --file $finalCovfile $CODE_COVERAGE_FINAL_DIR/*${CODE_COVERAGE_FILE_SUFFIX}
	sudo chmod -R $DIRS_PERMISSIONS $CODE_COVERAGE_COMMIT_DIR
	
	codeCoverageSummary=$CODE_COVERAGE_FINAL_DIR/$CODE_COVERAGE_SUMMARY_FILE_NAME
	covdir --file $finalCovfile >> $codeCoverageSummary

	

	scp -r $finalCovfile $CURRENT_NFS_RESULTS_DIR
fi

echo "#!/bin/sh
	export CODE_COVERAGE_SUMMARY='$codeCoverageSummary'
	export CODE_COVERAGE_AGGREIGATED_COVFILE='$finalCovfile'
	
" > $SOURCES_DIR/analyzeExports.sh
