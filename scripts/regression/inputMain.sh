#!/bin/bash

 # control flags
	# user-defined:
configureFlag=0
executeFlag=0
distributeFlag=0
analizeFlag=0
setupFlag=0
	# not user-defined"
controlFlag=1
collectFlag=1
viewFlag=1
exitFlag=1
 # --
testRunFlag=0
coFlag=0	
rpmFlag=0
linesToExecute=-1
currentTestsDir=""
csvFile=""
testsFolderDir=""
hadoopDir=""
resServer=""
localResultsDir=""
dataSetType=""
svnHadoop=""
svnRevision=""
svnTrunk=""
rpmJar=""
reportMailingList=""
reportComment=""
hadoopClasspath=""
svnRpmBuild=""
javaHome=""
ramSize=0
nfsResultsDir=""
reportSubject=""
testRunDataset=""
reportInput=""
coresDir=""
coresPattern=""

# the defalut for logs.server is the master

usage (){
        echo "
usage $0

		<options>
	-b					build the tests-files
	-e					execute the test
	-be					build and execute the test (default)
	-r					generation report from the results
	-d					distribute the report to contacts
	-c					taking the hadoop from the svn
	-p					installing rpm
	-s					for skip NFS option
	-D					enter parameter
	 
	 	<parameters>	 syntax: -D{parameter}={value}	

	hadoop.home				hadoop home directoory
	csv					csv input file directoory
	scripts					directory of the scripts that used in this script
	logs.server				the name of the machine that collects the executions details and statistics
	logs.local.dir					the directory for placing the statistics into it
	dataset.type				'node' for size per node, 'cluster' for size for whole cluster
	tests.folder				directory for creating the test-folder. the directory must have correct RWX premmitions
	tests.current				if choosing -e option, the directory of the desired tests can placed here 
 	tests.num				the count of tests to run	 
	results.nfs.dir					directory for the results to be saved in it
	hadoop.classpath			for setting the parameter HADOOP_CLASSPATH in case of using the UDA rpm
	svn.hadoop				URL to the desired hadoop version from the svn
	svn.revision				for using revision which deffer from the current revisin
	svn.rpm.build				URL to the script that build the rpm
	rpm.jar					the name of the jar of rpm to install	
	report.mailing.list			list of comma separrated mail-usernames, to sent them the result report
	report.comment				comment to add to the report
	ram.size				the RAM of any machine in the cluster (in Gb)
		
		The defalut values can be found in the default.sh file
"
}

while getopts ":beadcrstD:" Option
do
	case ${Option} in
    		"b"     ) configureFlag=1 ;;
	    	"e"     ) executeFlag=1 ;;
			"a"		) analizeFlag=1 ;;
			"d"		) distributeFlag=1 ;;
			"c"     ) coFlag=1 ;;
			"r"		) rpmFlag=1 ;;
			"s"     ) setupFlag=1 ;;
			"t"     ) testRunFlag=1 ;;
    		"D"     ) 
			param=${OPTARG:0:`expr index $OPTARG =`-1}
			value=${OPTARG:`expr index $OPTARG =`}
			case ${param} in
				hadoop.home		) hadoopDir=$value ;;
				hadoop.classpath	) hadoopClassPath=$value ;;
				csv		) csvFile=$value ;;
				svn.hadoop	) svnHadoop=$value ;;
				svn.trunk	) svnTrunk=$value ;;
				svn.rpm.build	) svnRpmBuild=$value ;;
				svn.revision	) svnRevision=$value ;;
				rpm.jar			) rpmJar=$value ;;
				#scripts		) scriptsDir=$value;;			
				tests.folder	) testsFolderDir=$value;;			
				tests.current	) currentTestsDir=$value;;	 		
				tests.num	) linesToExecute=$value;;	 		
				logs.server	) resServer=$value;;			
				logs.local.dir		) localResultsDir=$value;;
				results.nfs.dir		) nfsResultsDir=$value;;
				dataset.type	) dataSetType=$value;;
				report.input	) reportInput=$value;;
				report.mailing.list	) reportMailingList=$value;;
				report.subject		) reportSubject=$value;;
				report.comment	) reportComment=$value;;
				ram.size	) ramSize=$value;;
				java.home	) javaHome=$value;;
				#mode.test.dataset	) testRunDataset=$value;;
				#cores.uda	) udaCoresDir=$value;;
				cores.dir	) coresDir=$value;;	
				cores.pattern	) coresPattern=$value;;
				*     		) echo "Unknown parameter chosen. enter -h for help"; exit $SEC ;;   # Default.	
			esac
			;;
		*     	) usage;  exit $SEC ;;   # Default.
	esac
done

if [ -z "$csvFile" ];then
	csvFile=$DEFAULT_CSV_FILE
fi

if [ -z "$testsFolderDir" ];then
	testsFolderDir=$DEFAULT_TEST_FOLDER_DIR
fi

if [ -z "$hadoopDir" ];then
    hadoopDir=$DEFAULT_HADOOP_DIR
fi

if [ -z "$hadoopClasspath" ];then
    hadoopClasspath=$DEFAULT_HADOOP_CLASSPATH
fi

if [ -z "$dataSetType" ];then
	dataSetType=$DEFAULT_DATA_SET_TYPE
fi

if [ -z "$localResultsDir" ];then
    localResultsDir=$DEFAULT_LOCAL_RESULTS_DIR
fi

if [ -z "$svnHadoop" ];then
    svnHadoop=$DEFAULT_SVN_HADOOP
fi

if [ -z "$svnTrunk" ];then
    svnTrunk=$DEFAULT_SVN_TRUNK
fi

if [ -z "$svnRpmBuild" ];then
    svnRpmBuild=$DEFAULT_SVN_RPM_BUILD
fi

if [ -z "$svnRevision" ];then
    svnRevision=$DEFAULT_SVN_REVISION
fi

if [ -z "$rpmJar" ];then
    rpmJar=$DEFAULT_RPM_JAR
fi

if [ -z "$reportMailingList" ];then
    reportMailingList=$DEFAULT_REPORT_MAILING_LIST
fi

if [ -z "$reportComment" ];then
    reportComment=$DEFAULT_REPORT_COMMENT
fi

if (($ramSize == 0));then
    ramSize=$DEFAULT_RAM_SIZE
fi

if [ -z "$javaHome" ];then
    javaHome=$DEFAULT_JAVA_HOME
fi

if [ -z "$reportSubject" ];then
    reportSubject=$DEFAULT_REPORT_SUBJECT
fi

if [ -z "$testRunDataset" ];then
    testRunDataset=$DEFAULT_TEST_RUN
fi

if [ -z "$reportInput" ];then
    reportInput=$DEFAULT_REPORT_INPUT
fi

if [ -z "$coresDir" ];then
    coresDir=$DEFAULT_CORES_DIR
fi

if [ -z "$coresPattern" ];then
    coresPattern=$DEFAULT_CORES_PATTERN
fi

#currentNfsResultsDir=$CURRENT_NFS_RESULTS_DIR
if [ -z "$nfsResultsDir" ];then
    nfsResultsDir=$DEFAULT_NFS_RESULTS_DIR
#else
#	mv -f $CURRENT_NFS_RESULTS_DIR $nfsResultsDir
#	currentNfsResultsDir=$nfsResultsDir/$CURRENT_DATE
fi

#hadoopVersion=`echo $(basename $hadoopDir) | sed s/[.]/_/g`
echo "
	#!/bin/sh
	
		# control flags
	export CONTROL_FLAG=$controlFlag
	export CONFIGURE_FLAG=$configureFlag
	export SETUP_FLAG=$setupFlag
	export EXECUTE_FLAG=$executeFlag
	export COLLECT_FLAG=$collectFlag
	export VIEW_FLAG=$viewFlag	
	export ANALIZE_FLAG=$analizeFlag
	export DISTRIBUTE_FLAG=$distributeFlag
	export EXIT_FLAG=$exitFlag
		# another flags
	export TEST_RUN_FLAG=$testRunFlag
	export CO_FLAG=$coFlag
	export RPM_FLAG=$rpmFlag
		# general envs
	export HADOOP_DIR='$hadoopDir'
	export CSV_FILE='$csvFile'
	export TEST_FOLDER_DIR='$testsFolderDir'
	export CURRENT_TESTS_DIR='$currentTestsDir'
	export LINE_TO_EXECUTE=$linesToExecute
	export RES_SERVER='$resServer'
	export LOCAL_RESULTS_DIR='$localResultsDir'
	export DATA_SET_TYPE='$dataSetType'
	export NFS_RESULTS_DIR='$nfsResultsDir'
	export SVN_HADOOP='$svnHadoop'
	export SVN_TRUNK='$svnTrunk'
	export SVN_RPM_BUILD='$svnRpmBuild'
	export SVN_REVISION='$svnRevision'
	export RPM_JAR='$rpmJar'
	export REPORT_MAILING_LIST='$reportMailingList'
	export REPORT_COMMENT='$reportComment'
	export REPORT_INPUT='$reportInput'
	export REPORT_SUBJECT='$reportSubject'
	export RAM_SIZE=$ramSize
	export JAVA_HOME='$javaHome'
	export HADOOP_CLASSPATH='$hadoopClasspath' 
	export TEST_RUN=$testRunDataset
	export CORES_DIR='$coresDir'
	export CORES_PATTERN='$coresPattern'
	#export CURRENT_NFS_RESULTS_DIR=$currentNfsResultsDir
" > $TMP_DIR/inputExports.sh
