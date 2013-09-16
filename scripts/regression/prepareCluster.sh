#!/bin/bash

echoPrefix=`eval $ECHO_PATTERN`

pdsh -w $ALL_SLAVES_BY_COMMAS "sudo rm -rf $BASE_DIR; mkdir $BASE_DIR"

for machine in $ALL_MACHINES_BY_SPACES;do
	bash $SCRIPTS_DIR/functionsLib.sh "set_hostnames" "$machine" "$machine" 
done

# CHECKING PRE-REQs - checking the log-dirs free space
echo "$echoPrefix: cheching pre-requests: bash $SCRIPTS_DIR/preReq.sh -n"
bash $SCRIPTS_DIR/preReq.sh -n
if (($? == $EEC3));then 
	exit $EEC3
fi	

if (($CODE_COVE_FLAG==1)); then

	codeCoverageDir=$BASE_DIR/$CODE_COVERAGE_DIR_NAME
	codeCoverageTemplateCovfileDir=$codeCoverageDir/$CODE_COVERAGE_TEMPLATE_COVFILE_DIR_NAME
	mkdir -p $codeCoverageTemplateCovfileDir
	
	codeCoverageResultsDir=$codeCoverageDir/$CODE_COVERAGE_FINAL_LOCAL_DIR_NAME
	mkdir $codeCoverageResultsDir

	codeCoverageCommitdir=$codeCoverageDir/$CODE_COVERAGE_COMMIT_DIR_NAME
	mkdir $codeCoverageCommitdir	
fi
 
echo "
	#!/bin/sh
	export CODE_COVERAGE_DIR='$codeCoverageDir'
	export CODE_COVERAGE_TEMPLATE_COVFILE_DIR='$codeCoverageTemplateCovfileDir'
	export CODE_COVERAGE_FINAL_DIR='$codeCoverageResultsDir'
	export CODE_COVERAGE_COMMIT_DIR='$codeCoverageCommitdir'
" > $SOURCES_DIR/prepareClusterExports.sh
