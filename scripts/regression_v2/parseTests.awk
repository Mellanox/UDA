#!/bin/awk -f

function getHeadersAndProperties()
{
	i=glbPSC
	confParamsFlag=0
	while ($i !~ /PARAMS_END/) # the last field by convantion is the sentinel. thats why we not use i<=NF
	{
		ind=index($i,daemonsParamsIndicator)
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
		else if ($i == emptyFieldFlag)
			execParams[headers[i]]=""
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

function manageInterface(pInterface)
{
	ending=""
		# THERE IS VERSIONS OF AWK THAT DON'T SUPPORT SWITCH CASE
	#switch (pInterface) {
	#	case "ib0":
	#		ending="ib"
	#	case "eth4":
	#		ending="10g"
	#	case "eth1":
	#		ending="1g"
	#	default:
	#		errorDesc = errorDesc "error in the interface of " $1 " - unknown interface \n" 
	#}
	if (pInterface==interfaceNameIb)
		ending=interfaceValueIb
	else if (pInterface==interfaceNameEthA)
		ending=interfaceValueEthA
	else if (pInterface==interfaceNameEthB)
		ending=interfaceValueEthB
	else if (pInterface=="")
		ending=""
	else
		errorDesc = errorDesc "error in " $1 " - unknown interface \n"

	plantInterface(ending)

	return ending
}

function plantInterface(pInterface)
{
	if (pInterface ~ /[A-Za-z0-9_]+/)
	{		
		split(execParams["mapred.job.tracker"], temp, ":")
		execParams["mapred.job.tracker"] = temp[1] "-" pInterface ":" temp[2]

		split(execParams["fs.default.name"], temp, ":")
		execParams["fs.default.name"] = temp[1] ":" temp[2] "-" pInterface ":" temp[3]
	}
}

function buildSlavesFiles(pSlavesCount,pInterface,pDir)
{
	currentSlaves=""
	totalSlaves=split(generalParams[glbSlaves],slaves,commaDelimitedPropsDelimiter)
	if (slaves[totalSlaves] !~ /[A-Za-z0-9_]+/) # to avoid ; (with or without spaces) at the end of the slaves line
			totalSlaves--
	if ((pSlavesCount == -1) || (pSlavesCount > totalSlaves))
			slavesFinalNum = totalSlaves
	else if (pSlavesCount == 0)
		currentSlaves = "localhost"	
	else
		slavesFinalNum = pSlavesCount

	for (i=1; i <= slavesFinalNum; i++)
		currentSlaves = currentSlaves slaves[i] pInterface "\n"

	system("echo -n > " pDir "/slaves")
	print currentSlaves >> pDir "/slaves"

	return slavesFinalNum

}

function buildMastersFile(pMaster)
{
	system("echo -n > " execDir "/masters")
	print pMaster >> execDir "/masters"
}

function buildConfigurationFiles()
{
	# initialling the files
	for (i in confFiles)
	{
		system("echo -n > " execDir "/" confFiles[i]) # -n is for avoiding blank line at the beginnig of XML file, which can cause runtime error
		print confFilesHeader >> execDir "/" confFiles[i]
	}
	for (i in DMfiles)
	{
		for (j in confFiles)
		{
			if (j ~ DMfiles[i])
			{
				# adding the proprety to the currect file
				xmlDir=execDir "/" confFiles[j]
				print "  <property>" >> xmlDir
				print "    <name>" DMprops[i]"</name>" >> xmlDir
				print "    <value>" execParams[headers[i]]"</value>" >> xmlDir
				print "  </property>" >> xmlDir
			}
		}
	}

	# finallizing the files
	for (i in confFiles)
		print "</configuration>" >> execDir "/" confFiles[i]
}

function exportMenager()
{	
	print "export PROGRAM='"execParams["program"] "'" >> execDir "/" exportsFile 
	print "export INTERFACE_ENDING='"ending "'" >> execDir "/" exportsFile 
	print "export MAX_MAPPERS="execParams["mapred.tasktracker.map.tasks.maximum"] >> execDir "/" exportsFile
	print "export DESIRED_MAPPERS="execParams["mapred.map.tasks"] >> execDir "/" exportsFile
	print "export MAX_REDUCERS="execParams["mapred.tasktracker.reduce.tasks.maximum"] >> execDir "/" exportsFile
	print "export DESIRED_REDUCERS="execParams["mapred.reduce.tasks"] >> execDir "/" exportsFile
	print "export NSAMPLES="execParams["samples"] >> execDir "/" exportsFile
	print "export SLAVES_COUNT="execParams["slaves"] >> execDir "/" exportsFile

	diskCount=split(execParams["dfs.data.dir"],srak,",")
	print "export DISKS="diskCount >> execDir "/" exportsFile
	if (execParams["mapred.reducetask.shuffle.consumer.plugin"] == "com.mellanox.hadoop.mapred.UdaShuffleConsumerPlugin")
		print "export SHUFFLE_CONSUMER=1" >> execDir "/" exportsFile
	else 
		print "export SHUFFLE_CONSUMER=0" >> execDir "/" exportsFile

	if (execParams["mapred.tasktracker.shuffle.provider.plugin"] == "com.mellanox.hadoop.mapred.UdaShuffleProviderPlugin")
		print "export SHUFFLE_PROVIDER=1" >> execDir "/" exportsFile
	else
		print "export SHUFFLE_PROVIDER=0" >> execDir "/" exportsFile
	
	if (execParams["mapred.compress.map.output"] == "true"){
		print "export COMPRESION_=1" >> execDir "/" exportsFile
		if (execParams["mapred.map.output.compression.codec"] == "com.hadoop.compression.lzo.LzoCodec")
			print "export COMPRESION_TYPE=LZO" >> execDir "/" exportsFile
		if (execParams["mapred.map.output.compression.codec"] == "org.apache.hadoop.io.compress.SnappyCodec")
			print "export COMPRESION_TYPE=Snappy" >> execDir "/" exportsFile
		
	}

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
			if (params[p] == teravalFlag)
				teraval=1
			else if (params[p] == teragenFlag)
				teragen=1	
		}		

		if (teraval == 1)
			print "export TERAVALIDATE=1" >> execDir "/" exportsFile
		else
			print "export TERAVALIDATE=0" >> execDir "/" exportsFile
			
		if ((lastTeragenParam != params[1]) || (teragen == 1))
			print "export TERAGEN=1" >> execDir "/" exportsFile
		else
			print "export TERAGEN=0" >> execDir "/" exportsFile
		lastTeragenParam=params[1]
	}
	else if (execParams["program"]~/pi/)
	{
		len=split(execParams["add_params"],params,/[[:space:]]*/)
		if (len == 2)
		{
			piMappers=params[1]
			piSamples=params[2]
		}
		else
		{
			piMappers=piMappersDefault
			piSamples=piSamplesDefault
		}
		print "export PI_MAPPERS=" piMappers >> execDir "/" exportsFile
		print "export PI_SAMPLES=" piSamples >> execDir "/" exportsFile
	}
}

function restartHandler()
{
	for (j in DMprops)
		currentDMs[j] = execParams[headers[j]]
	
	execInterface = manageInterface(execParams["mapred.tasktracker.dns.interface"])
	if (execInterface ~ /[A-Za-z0-9_]+/)
		execInterface= "-" execInterface
		
	execSlaves=buildSlavesFiles(execParams["slaves"],execInterface,execDir) # execParams[3] is the slaves count
	buildMastersFile(generalParams[glbMasters] execInterface)  # BE AWARE THAT THERE IS NO COMMA HERE - THIS IS SINGLE PARAMETERS
	buildConfigurationFiles()
}

function keyInDictValues(key,dict)
{
	for (i in dict)
	{
		if (dict[i] == key)
			return 1
	}
	return 0
}

BEGIN{
	FS=","

	glbPSC = 2 # PSC = Parameters Start Column in the CSV file	
	
	daemonsParamsIndicator="@"
	teravalFlag="v"
	teragenFlag="g"
	endTypeFlag="end_flag"
	emptyFieldFlag="x"
	
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
	
	endingProps[1]="nrFiles"
	endingProps[2]="fileSize"
	endingProps[3]=endTypeFlag

	interfaceNameIb="ib0"
	interfaceNameEthA="eth4"
	interfaceNameEthB="eth1"
	interfaceValueIb="ib"
	interfaceValueEthA="10g"
	interfaceValueEthB="1g"
	
	piMappersDefault=10
	piSamplesDefault=100
	isSnappyExist=0
	isLZOExist=0
	
	confFilesHeader="<?xml version=\"1.0\"?>\n<?xml-stylesheet type=\"text/xsl\" href=\"configuration.xsl\"?>\n<configuration>"
	executionPrefix="bin/hadoop jar"
	bashScriptsHeadline="#!/bin/sh"

	maxSlaves=0
	addParamsTotalCount=3
	testsCount=0
	lastTeragenParam=-1
	errorDesc=""

		# creating a file with the general exports of this session
	generalDir=testsFolderDir"/general.sh"
	exportsFile="exports.sh"

	system("echo '"bashScriptsHeadline "' > " generalDir)
}

($1 ~ /^#/){
	tmpProp=substr($1,2,length($1)-1)
	tmpVal=$2
	gsub(commaDelimitedPropsDelimiter,FS,tmpVal)
	generalParams[tmpProp]=$2		# for use in this script
	print "export csv" tmpProp "='" tmpVal "'" >> generalDir	# for use in runTest.sh
}

($1 ~ /DEFAULT(|S)/){
        for (i in headers)
         	defaults[i]= $i	
}

($1 ~ /HEADERS/ ){
	getHeadersAndProperties()
	availableSlavesCount=buildSlavesFiles(-1,"",testsFolderDir)
}

($1 !~ /^#/) && ($1 !~ /HEADERS/) && ($1 !~ /DEFAULT(|S)/) && (match($0, "[^(\r|\n|,)]") > 0){ # \r is kind of line break character, like \n. \r is planted at the end of the record, $0. the purpuse of this match function is to avoid rows of commas (only), which can be part of csv file  
	if (($2 == 0) || (($2 == "") && (defaults[2] == 0))) # if this row is not for execution
		next
		
	# ELSE:
	restartFlag=0

		# saving parameters from the last execution, before starting new one
	lastSlavesCount = execParams["slaves"]

	getDefaultsIfNeeded()	# taking inputs from the DEFAULT line if neccesary 

	if (execParams["slaves"] == 0)
		next
	
	testsCount++

	dirName="test" testsCount
	if ($1 ~ /[[:space:]]*/)
		dirName=dirName "-" $1
	execDir=testsFolderDir "/" dirName
		# Creating the folder and exports file for the execution	
	system("mkdir " execDir " ; echo '"bashScriptsHeadline "' > "execDir"/"exportsFile)
	print "export EXEC_NAME='" $1 "'" >> execDir"/"exportsFile

		# finding the maximun amount of slaves in the tests

	if (execParams["slaves"] > availableSlavesCount)
		execParams["slaves"]=availableSlavesCount
		
	if (execParams["slaves"] > maxSlaves)
		maxSlaves=execParams["slaves"]

	#commaDelimitedProps[glbSlaves]=generalParams[glbSlaves]
	manageCommaDelimitedProps(commaDelimitedProps)
	manageMinusPrefixProps(minusPrefixProps)
	manageBooleanValueProps(booleanValueProps)

		# managing the parameters for the execution
	#confParams="\n"
	confParams=""
	endParams=""
	for (i in CMDprops)
	{
		propName=CMDprops[i]
		propValue=execParams[headers[i]]
		if (propValue != "")
		{
			if (keyInDictValues(propName,endingProps)==1)
			{
				if (propName == endTypeFlag)
					endParams = endParams "-" propValue " "
				else
					endParams = endParams "-" propName " " propValue " "
			}
			else
				confParams = confParams "-D" propName "=" propValue " "
			
			if ( match(propValue, /com.hadoop.compression.lzo.LzoCodec/) ==1 ){
				isLZOExist=1
				print "isLZOExist" ,isLZOExist
			}
			if ( match(propValue, /org.apache.hadoop.io.compress.SnappyCodec/) ==1 ){
				isSnappyExist=1
				print "isSnappyExist" ,isSnappyExist
			}
		}
	}
	#CMD= executionPrefix " " execParams["jar_dir"] " " execParams["program"] " " confParams 
	#if (execParams["program"]~/TestDFSIO/)
	#	CMD= CMD " " endParams
	#print "export CMD='" CMD "'" >> execDir "/" exportsFile
	print "export CMD_PREFIX='" executionPrefix "'" >> execDir "/" exportsFile
	print "export CMD_JAR='" execParams["jar_dir"] "'" >> execDir "/" exportsFile
	print "export CMD_PROGRAM='" execParams["program"] "'" >> execDir "/" exportsFile
	print "export CMD_D_PARAMS='" confParams "'" >> execDir "/" exportsFile
	print "export CMD_END_PARAMS='" endParams "'" >> execDir "/" exportsFile
		# checking if there is a need to rise/restart hadoop
		
	if (lastSlavesCount != execParams["slaves"])
		restartFlag=1
	else # checking if there is changes is daemon-parameters since the last execution
	{
		for (i in DMprops)
			if (execParams[headers[i]] != currentDMs[i]){
				restartFlag=1
				break
			}
	}

	if (restartFlag==1)
	{
		print "export RESTART_HADOOP=1" >> execDir "/" exportsFile
		restartHandler()
	}
	else
		print "export RESTART_HADOOP=0" >> execDir "/" exportsFile

	if (testsCount==1)
		print "export FIRST_STARTUP=1" >> execDir "/" exportsFile
	else
		print "export FIRST_STARTUP=0" >> execDir "/" exportsFile

	exportMenager()

	# check for errors
	if (execParams["mapred.tasktracker.map.tasks.maximum"] < execParams["mapred.tasktracker.reduce.tasks.maximum"])
		errorDesc = errorDesc "error in " $1 " - more reducers-slots than mappers-slots \n"
}

END{
	if (maxSlaves > 0)
	{
		split(generalParams[glbSlaves], temp, commaDelimitedPropsDelimiter)
		relevantSlavesSpace=temp[1]
		relevantSlavesComma=temp[1]
		for (i=2; i <= maxSlaves; i++)
		{
			relevantSlavesSpace=relevantSlavesSpace " " temp[i]
			relevantSlavesComma=relevantSlavesComma "," temp[i]
		}
	}
	else
	{
		relevantSlavesSpace=""
		relevantSlavesComma=""
		errorDesc = errorDesc "error in general configuration - no slaves selected \n"
	}

	if ( isLZOExist==1 ){
		print "export LZO=1" >> generalDir
		print "export COMPRESSION=1" >> generalDir
	}
	else if ( isSnappyExist==1 ){
		print "export Snappy=1"  >> generalDir
		print "export COMPRESSION=1" >> generalDir
	}
	else
		print "export COMPRESSION=0" >> generalDir

	print "export RELEVANT_SLAVES_BY_SPACES='" relevantSlavesSpace "'" >> generalDir
	print "export RELEVANT_SLAVES_BY_COMMAS='" relevantSlavesComma "'" >> generalDir
	print "export TESTS_COUNT=" testsCount >> generalDir
	print "export DEFAULT_RES_SERVER='" generalParams[glbMasters]  "'"  >> generalDir
	print "export ERRORS='" errorDesc "'" >> generalDir
	print errorDesc
	isSnappyExist=0
	isLZOExist=0
}

