#!/bin/awk -f

function getHeadersAndProperties()
{
	i=glbPSC
	confParamsFlag=0
	while ($i !~ /PARAMS_END/) # the last field by convantion is the sentinel. thats why we not use i<=NF
	{
		ind=index($i,"@")
		if (ind > 0)	# in case of daemon parameter
		{
			DMprops[i]=substr($i,1,ind-1)	# gets the daemon-property
			DMfiles[i]= substr($i,ind+1,length($i)+1-ind)	# gets the daemon-property correct configuration file
			headers[i]=DMprops[i]
		}
		else if (confParamsFlag) # there is no convention differance between non-daemon parameters and environment parameters (input/output dir etc.. so flag is needed to distinguish between them
		{
			CMDprops[i]=$i
			headers[i]=$i
		}
		else if ($i ~/CONF_PARAMS/)
			confParamsFlag=1
		else
		{
			envParams[i]=$i # environment parameters are parameters such jar file, input/output dir etc.  
			headers[i]=$i
		}
		i++
	}
}

function manageCommaDelimitedProps(commaProps)
{
	for (i in commaProps)
		gsub(commaDelimitedPropsDelimiter,FS,execParams[commaProps[i]])
}

function manageMinusPrefixProps(minusProps)
{
    for (i in minusProps)
		if (execParams[minusProps[i]] != "")
			execParams[minusProps[i]]="-Xmx"execParams[minusProps[i]]"m"
}

function getDefaultsIfNeeded()
{
        for (i in defaults){
                if ($i == "")
                        execParams[headers[i]]=defaults[i]
                else
                        execParams[headers[i]]=$i
        }
}

function manageBooleanValueProps(booleanProps)
{
	for (i in booleanProps)
	{
		if (execParams[booleanProps[i]]=="FALSE")
			execParams[booleanProps[i]]="false"
		else if (execParams[booleanProps[i]]=="TRUE")
			execParams[booleanProps[i]]="true"
		else if ((execParams[booleanProps[i]]!="true") && (execParams[booleanProps[i]]!="false") && (execParams[booleanProps[i]]!~/[[:space:]]*/))
			errorDesc = errorDesc "error in test #" $testsCount " - wrong input at " booleanProps[i] "\n"		
	}
}

function exportMenager()
{	
	print "export PROGRAM='"execParams["program"] "'" >> execDir "/" exportsFile 
	print "export DESIRED_MAPPERS="execParams["mapred.map.tasks"] >> execDir "/" exportsFile
	print "export DESIRED_REDUCERS="execParams["mapred.reduce.tasks"] >> execDir "/" exportsFile
	print "export NSAMPLES="execParams["samples"] >> execDir "/" exportsFile

	if (execParams["mapred.reducetask.shuffle.consumer.plugin"] == "com.mellanox.hadoop.mapred.UdaShuffleConsumerPlugin")
		print "export SHUFFLE_CONSUMER=1" >> execDir "/" exportsFile
	else 
		print "export SHUFFLE_CONSUMER=0" >> execDir "/" exportsFile

	manageAddParams()
}

function manageAddParams()
{
	for (i=1; i<=addParamsTotalCount; i++)
		perams[i]=-1

	if (execParams["program"]~/terasort/)
	{
		teragen=0
		teraval=0

		split(execParams["add_params"],params,/[[:space:]]*/)
		print "export DATA_SET="params[1] >> execDir "/" exportsFile

		for (p in params)
		{
			if (params[p] == "v")
				teraval=1
			else if (params[p] == "g")
				teragen=1	
		}		

		if (teraval == 1)
			print "export TERAVALIDATE=1" >> execDir "/" exportsFile
		else
			print "export TERAVALIDATE=0" >> execDir "/" exportsFile

		if ((lastTeragenParam != params[3]) || (teragen == 1))
			print "export TERAGEN=1" >> execDir "/" exportsFile
		else
			print "export TERAGEN=0" >> execDir "/" exportsFile
		lastTeragenParam=params[1]
	}
}

BEGIN{
	FS=","

	glbPSC = 2 # PSC = Parameters Start Column in the CSV file	
	
		# some usefull properties from the CSV file 
	glbMasters= "MASTER"
	glbSlaves="SLAVES"

		# the names of the configuration files
	confFiles["mapred"]="mapred-site.xml"
	confFiles["hdfs"]="hdfs-site.xml"
	confFiles["core"]="core-site.xml"

		# properties with can have multiple values, seperating bt commas. because the awk is works with Comma Seperated file, those parameters should be seperating by other delimiter
	commaDelimitedPropsDelimiter=";"
	commaDelimitedProps[1]="dfs.data.dir"
	commaDelimitedProps[2]="dfs.name.dir"
	commaDelimitedProps[3]="hadoop.tmp.dir"
	commaDelimitedProps[4]="mapred.local.dir"	

	minusPrefixProps[1]="mapred.map.child.java.opts" 	# for hadoop 1.x
	minusPrefixProps[2]="mapred.reduce.child.java.opts" # for hadoop 1.x
	minusPrefixProps[3]="mapred.child.java.opts"		# for hadoop 0.20.2

	booleanValueProps[1]="mapred.map.tasks.speculative.execution"
    booleanValueProps[2]="mapred.reduce.tasks.speculative.execution"
	
	confFilesHeader="<?xml version=\"1.0\"?>\n<?xml-stylesheet type=\"text/xsl\" href=\"configuration.xsl\"?>\n<configuration>"
	jarDirHeader="jar_dir"
	executionPrifix="hadoop jar"
	bashScriptsHeadline="#!/bin/sh"

	maxSlaves=0
	addParamsTotalCount=3
	testsCount=0
	lastTeragenParam="" # for avoiding automathed teragen in the first test
	errorDesc=""

	
		# creating a file with the general exports of this session
	generalDir=testsFolderDir"/general.sh"
	exportsFile="exports.sh"

	system("echo '"bashScriptsHeadline "' > " generalDir)
}

($1 ~ /DEFAULT(|S)/){
        for (i in headers)
         	defaults[i]= $i	
}

($1 ~ /HEADERS/ ){
	getHeadersAndProperties()
}

($1 !~ /^#/) && ($1 !~ /HEADERS/) && ($1 !~ /DEFAULT(|S)/) && (match($0, "[^(\r|\n|,)]") > 0){ # \r is kind of line break character, like \n. \r is planted at the end of the record, $0. the purpuse of this match function is to avoid rows of commas (only), which can be part of csv file  
	if (($2 == 0) || (($2 == "") && (defaults[2] == 0))) # if this row is not for execution
		next
		
	# ELSE:
	restartFlag=0		
	testsCount++

	dirName="test" testsCount
	if ($1 ~ /[[:space:]]*/)
		dirName=dirName "-" $1
	execDir=testsFolderDir "/" dirName
		# Creating the folder and exports file for the execution	
	system("mkdir " execDir " ; echo '"bashScriptsHeadline "' > "execDir"/"exportsFile)
	print "export EXEC_NAME='" $1 "'" >> execDir"/"exportsFile

	stat=0

	getDefaultsIfNeeded()	# taking inputs from the DEFAULT line if neccesary 


	manageCommaDelimitedProps(commaDelimitedProps)
	manageMinusPrefixProps(minusPrefixProps)
	manageBooleanValueProps(booleanValueProps)

		# managing the parameters for the execution
	#confParams="\n"
	confParams=""
	for (i in CMDprops)
		if (execParams[headers[i]] != "")
			#confParams = confParams "-D" CMDprops[i] "=" execParams[i] " \\\n"
			confParams = confParams "-D" CMDprops[i] "=" execParams[headers[i]] " "

	CMD= executionPrifix " " execParams["jar_dir"] " " execParams["program"] " " confParams " "
	print "export CMD='" CMD "'" >> execDir "/" exportsFile

	exportMenager()
}

END{
	print "export MAX_SLAVES=" maxSlaves >> generalDir
	print "export TESTS_COUNT=" testsCount >> generalDir
	print "export DEFAULT_RES_SERVER='" generalParams[glbMasters]  "'"  >> generalDir
	print "export ERRORS='" errorDesc "'" >> generalDir
	print errorDesc
}
