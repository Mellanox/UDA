#!/bin/bash

 # control flags
	# user-defined:
configureFlag=0
codeCoverageFlag=0
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
unspreadConfFlag=0
coFlag=0	
rpmFlag=0
zipFlag=0
linesToExecute=-1
currentConfDir=""
csvFile=""
confFolderDir=""
hadoopHome=""
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
reportInput=""
coresDir=""
coresPattern=""
rpmBuildDir=""
reportName=""
gitHadoopsDir=""
gitHadoopVersion=""
gitMasterDir=""

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

while getopts ":beadcrstuziD:" Option
do
	case ${Option} in
    		"b"     ) configureFlag=1 ;;
			"s"     ) setupFlag=1 ;;
	    	"e"     ) executeFlag=1 ;;
			"a"		) analizeFlag=1 ;;
			"d"		) distributeFlag=1 ;;
			"c"     ) coFlag=1 ;;
			"r"		) rpmFlag=1 ;;
			"t"     ) testRunFlag=1 ;;
			"u"     ) unspreadConfFlag=1 ;;
			"z"		) zipFlag=1 ;;
			"i"     ) codeCoverageFlag=1 ;;
    		"D"     ) 
			param=${OPTARG:0:`expr index $OPTARG =`-1}
			value=${OPTARG:`expr index $OPTARG =`}
			case ${param} in
				hadoop.home		) hadoopHome=$value ;;
				hadoop.classpath	) hadoopClassPath=$value ;;
				csv		) csvFile=$value ;;
				svn.hadoop	) svnHadoop=$value ;;
				svn.trunk	) svnTrunk=$value ;;
				svn.rpm.build	) svnRpmBuild=$value ;;
				svn.revision	) svnRevision=$value ;;
				rpm.jar			) rpmJar=$value ;;
				rpm.build		) rpmBuildDir=$value ;;
				lzo.jar			) lzoJar=$value ;;
				#scripts		) scriptsDir=$value;;			
				conf.folder	) confFolderDir=$value;;			
				conf.current	) currentConfDir=$value;;	 		
				tests.num	) linesToExecute=$value;;	 		
				logs.server	) resServer=$value;;			
				logs.local.dir		) localResultsDir=$value;;
				results.nfs.dir		) nfsResultsDir=$value;;
				dataset.type	) dataSetType=$value;;
				report.input	) reportInput=$value;;
				report.mailing.list	) reportMailingList=$value;;
				report.name	) reportName=$value;;
				report.subject		) reportSubject=$value;;
				report.comment	) reportComment=$value;;
				ram.size	) ramSize=$value;;
				java.home	) javaHome=$value;;
				#cores.uda	) udaCoresDir=$value;;
				cores.dir	) coresDir=$value;;	
				cores.pattern	) coresPattern=$value;;
				git.hadoops.dir	) gitHadoopsDir=$value;;
				git.hadoop.version	) gitHadoopVersion=$value;;
				git.master.dir	) gitMasterDir=$value;;	
				*     		) echo "Unknown parameter chosen. enter -h for help"; exit $SEC ;;   # Default.	
			esac
			;;
		*     	) usage;  exit $SEC ;;   # Default.
	esac
done

if [ -z "$csvFile" ];then
	csvFile=$DEFAULT_CSV_FILE
fi

if [ -z "$confFolderDir" ];then
	confFolderDir=$DEFAULT_CONF_FOLDER_DIR
fi

if [ -z "$hadoopHome" ];then
    hadoopHome=$DEFAULT_MY_HADOOP_HOME
	echo "DEFAULT_MY_HADOOP_HOME $DEFAULT_MY_HADOOP_HOME"
	#exit $SEC
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
    svnRpmBuild=$DEFAULT_TRUNK_RPM_BUILD_RELATIVE_PATH
fi

if [ -z "$svnRevision" ];then
    svnRevision=$DEFAULT_SVN_REVISION
fi

if [ -z "$rpmJar" ];then
    rpmJar=$DEFAULT_RPM_JAR
fi

if [ -z "$lzoJar" ];then
    lzoJar=$DEFAULT_LZO_JAR
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

if [ -z "$reportName" ];then
    reportName=$DEFAULT_REPORT_NAME
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

if [ -z "$rpmBuildDir" ];then
    rpmBuildDir=$DEFAULT_RPMBUILD_DIR
fi

if [ -z "$nfsResultsDir" ];then
    nfsResultsDir=$DEFAULT_NFS_RESULTS_DIR
fi

if [ -z "$gitHadoopsDir" ];then
    gitHadoopsDir=$DEFAULT_GIT_HADOOPS_DIR
fi

if [ -z "$gitHadoopVersion" ];then
    gitHadoopVersion=$DEFAULT_GIT_HADOOP_VERSION
fi

if [ -z "$gitMasterDir" ];then
    gitMasterDir=$DEFAULT_GIT_MASTER_DIR
fi

#hadoopVersion=`echo $(basename $hadoopHome) | sed s/[.]/_/g`
echo "
	#!/bin/sh
	
		# control flags
	export CONTROL_FLAG=$controlFlag
	export CONFIGURE_FLAG=$configureFlag
	export CODE_COVE_FLAG=$codeCoverageFlag
	export SETUP_FLAG=$setupFlag
	export EXECUTE_FLAG=$executeFlag
	export COLLECT_FLAG=$collectFlag
	export VIEW_FLAG=$viewFlag	
	export ANALIZE_FLAG=$analizeFlag
	export DISTRIBUTE_FLAG=$distributeFlag
	export EXIT_FLAG=$exitFlag
		# another flags
	export TEST_RUN_FLAG=$testRunFlag
	export UNSPREAD_CONF_FLAG=$unspreadConfFlag
	export CO_FLAG=$coFlag
	export RPM_FLAG=$rpmFlag
	export ZIP_FLAG=$zipFlag
		# general envs
	export MY_HADOOP_HOME='$hadoopHome'
	export CSV_FILE='$csvFile'
	export CONF_FOLDER_DIR='$confFolderDir'
	export CURRENT_TESTS_DIR='$currentConfDir'
	export LINE_TO_EXECUTE=$linesToExecute
	export RES_SERVER='$resServer'
	#export LOCAL_RESULTS_DIR='$localResultsDir'
	export DATA_SET_TYPE='$dataSetType'
	export NFS_RESULTS_DIR='$nfsResultsDir'
	export SVN_HADOOP='$svnHadoop'
	#export SVN_TRUNK='$svnTrunk'
	#export TRUNK_RPM_BUILD_RELATIVE_PATH='$svnRpmBuild'
	export SVN_REVISION='$svnRevision'
	export RPM_JAR='$rpmJar'
	export LZO_JAR='$lzoJar'
	export REPORT_MAILING_LIST='$reportMailingList'
	export REPORT_NAME='$reportName'
	export REPORT_COMMENT='$reportComment'
	export REPORT_INPUT='$reportInput'
	export REPORT_SUBJECT='$reportSubject'
	export RAM_SIZE=$ramSize
	#export JAVA_HOME='$javaHome'
	#export HADOOP_CLASSPATH='$hadoopClasspath' 
	#export CORES_DIR='$coresDir'
	#export CORES_PATTERN='$coresPattern'
	#export RPMBUILD_DIR='$rpmBuildDir'
	#export CURRENT_NFS_RESULTS_DIR=$currentNfsResultsDir
	export GIT_HADOOPS_DIR='$gitHadoopsDir'
	export GIT_HADOOP_VERSION='$gitHadoopVersion'
	export GIT_MASTER_DIR='$gitMasterDir'
" > $TMP_DIR/inputExports.sh
