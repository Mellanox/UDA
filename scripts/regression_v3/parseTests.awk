#!/bin/awk -f

function getHeadersAndProperties()
{
		# cleanning the arrays	
	split("", headers)
	split("", DMprops)
	split("", DMfiles)
	split("", CMDprops)
	split("", envParams)
	
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

function getDefaultsIfNeeded()
{
	for (i in defaults){

		if (($i == "") )
			execParams[headers[i]]=defaults[i]
		else if ($i != emptyFieldFlag)
			execParams[headers[i]]=$i
	}
}

function manageCommaDelimitedProps(commaProps)
{
	for (i in commaProps)
		gsub(commaDelimitedPropsDelimiter,FS,execParams[commaProps[i]])
}

function manageCreatingDirProps(dirProps)
{
	for (i in dirProps)
	{
		split(execParams[dirProps[i]], tmpDirs, FS)
		for (j in tmpDirs)
			dirsForCreation[tmpDirs[j]]="stam"
	}
}

function manageMinusPrefixProps(minusProps)
{
    for (i in minusProps)
		if (execParams[minusProps[i]] ~ /^[0-9]+$/) # regex for only numbers
			execParams[minusProps[i]]="-Xmx"execParams[minusProps[i]]"m"
		else
			execParams[minusProps[i]]="\"" execParams[minusProps[i]] "\""
}

function manageRandomWriteGenerateProps(randomWriteProps)
{
	ret=""
	for (i in randomWriteProps)
		ret=ret "-D" randomWriteProps[i] "=" execParams[randomWriteProps[i]] " "
		
	return ret
}

function manageRandomTextWriteGenerateProps(randomTextWriteProps)
{
	ret=""
	for (i in randomTextWriteProps)
		ret=ret "-D" randomTextWriteProps[i] "=" execParams[randomTextWriteProps[i]] " "
		
	return ret
}

function formatNumber(num,digits)
{
	# right now supporting only digits=2
	numLen=length(num)
	if (numLen == 1)
		return "0" num
	return num
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
			daemonValue=execParams[headers[i]]
			if ((j ~ DMfiles[i]) && (daemonValue != ""))
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
	#for (i in headers)
	#	if (() || () | ())
	#		print "FROM HEADERS: " headers[i]
	if ("nrFiles" in execParams)
		print "export NR_FILES="execParams["nrFiles"] >> execDir "/" exportsFile
	if ("log_num_mtt" in execParams)
		print "export LOG_NUM_MTT="execParams["log_num_mtt"] >> execDir "/" exportsFile
	if ("log_mtts_per_seg" in execParams)
		print "export LOG_MTTS_PER_SEG="execParams["log_mtts_per_seg"] >> execDir "/" exportsFile

	diskCount=split(execParams["dfs.data.dir"],srak,",")
	print "export DISKS_COUNT="diskCount >> execDir "/" exportsFile
	if (execParams["mapred.reducetask.shuffle.consumer.plugin"] == "com.mellanox.hadoop.mapred.UdaShuffleConsumerPlugin")
		print "export SHUFFLE_CONSUMER=1" >> execDir "/" exportsFile
	else 
		print "export SHUFFLE_CONSUMER=0" >> execDir "/" exportsFile

	if (execParams["mapred.tasktracker.shuffle.provider.plugin"] == "com.mellanox.hadoop.mapred.UdaShuffleProviderPlugin")
		print "export SHUFFLE_PROVIDER=1" >> execDir "/" exportsFile
	else
		print "export SHUFFLE_PROVIDER=0" >> execDir "/" exportsFile
	
	if (execParams["mapred.compress.map.output"] == "true"){
		print "export COMPRESSION=1" >> execDir "/" exportsFile
		if (execParams["mapred.map.output.compression.codec"] == "com.hadoop.compression.lzo.LzoCodec")
			print "export COMPRESSION_TYPE=LZO" >> execDir "/" exportsFile
		if (execParams["mapred.map.output.compression.codec"] == "org.apache.hadoop.io.compress.SnappyCodec")
			print "export COMPRESSION_TYPE=SNAPPY" >> execDir "/" exportsFile
		
	}
	else {
		print "export COMPRESSION=0" >> execDir "/" exportsFile
	}
	

	manageAddParams()
}

function manageAddParams()
{
	for (i=1; i<=addParamsTotalCount; i++)
		perams[i]=-1

	if ((execParams["program"]~/terasort/) || (execParams["program"]~/sort/) || (execParams["program"]~/wordcount/))
	{
		teragen=0
		teraval=0
		randomWrite=0
		randomTextWrite=0
		
		split(execParams["add_params"],params,/[[:space:]]*/)
		print "export DATA_SET="params[1] >> execDir "/" exportsFile

		for (p in params)
		{
			if (params[p] == teravalFlag)
				teraval=1
			else if (params[p] == teragenFlag)
				teragen=1	
			else if (params[p] == randomWriteFlag)
				randomWrite=1
			else if (params[p] == randomTextWriteFlag)
				randomTextWrite=1
		}		

		if (teraval == 1)
			print "export TERAVALIDATE=1" >> execDir "/" exportsFile
		else
			print "export TERAVALIDATE=0" >> execDir "/" exportsFile
		
		if (teragen == 1)
		{
			if (lastTeragenParam != params[1])
				print "export TERAGEN=2" >> execDir "/" exportsFile
			else
				print "export TERAGEN=1" >> execDir "/" exportsFile
			lastTeragenParam=params[1]
		}
		else
			print "export TERAGEN=0" >> execDir "/" exportsFile
	
		if (randomWrite == 1)
		{
			if (lastRandonWriteParam != params[1])
				print "export RANDOM_WRITE=2" >> execDir "/" exportsFile
			else
				print "export RANDOM_WRITE=1" >> execDir "/" exportsFile
			lastRandonWriteParam=params[1]
		}
		else
			print "export RANDOM_WRITE=0" >> execDir "/" exportsFile
	
		if (randomTextWrite == 1)
		{
			if (lastRandonTextWriteParam != params[1])
				print "export RANDOM_TEXT_WRITE=2" >> execDir "/" exportsFile
			else
				print "export RANDOM_TEXT_WRITE=1" >> execDir "/" exportsFile
			lastRandonTextWriteParam=params[1]
		}
		else
			print "export RANDOM_TEXT_WRITE=0" >> execDir "/" exportsFile
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
	split("", currentDMs)

	for (j in DMprops)
		currentDMs[j] = execParams[headers[j]]
	
	execInterface = manageInterface(execParams["mapred.tasktracker.dns.interface"])
	if (execInterface ~ /[A-Za-z0-9_]+/)
		execInterface= "-" execInterface
		
	execSlaves=buildSlavesFiles(execParams["slaves"],execInterface,execDir) # execParams[3] is the slaves count
	buildMastersFile(generalParams[glbMasters] execInterface)  # BE AWARE THAT THERE IS NO COMMA HERE - THIS IS SINGLE PARAMETERS
	buildConfigurationFiles()
}

function valueInDict(key,dict)
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
	samplesHeaderPlace=2
	
	daemonsParamsIndicator="@"
	teravalFlag="v"
	teragenFlag="g"
	randomWriteFlag="w"
	randomTextWriteFlag="t"
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

	creatingDirPropsDelimiter=commaDelimitedPropsDelimiter
	creatingDirProps[1]="dfs.data.dir"
	creatingDirProps[2]="dfs.name.dir"
	creatingDirProps[3]="hadoop.tmp.dir"
	creatingDirProps[4]="mapred.local.dir"
	
	minusPrefixProps[1]="mapred.map.child.java.opts" 	# for hadoop 1.x
	minusPrefixProps[2]="mapred.reduce.child.java.opts" # for hadoop 1.x
	minusPrefixProps[3]="mapred.child.java.opts"		# for hadoop 0.20.2

	booleanValueProps[1]="mapred.map.tasks.speculative.execution"
    booleanValueProps[2]="mapred.reduce.tasks.speculative.execution"

	randomWriteGenerateProps[1]="test.randomwrite.min_key"
	randomWriteGenerateProps[2]="test.randomwrite.max_key"
	randomWriteGenerateProps[3]="test.randomwrite.min_value"
	randomWriteGenerateProps[4]="test.randomwrite.max_value"
	
	randomTextWriteGenerateProps[1]="test.randomtextwrite.min_words_key"
	randomTextWriteGenerateProps[2]="test.randomtextwrite.max_words_key"
	randomTextWriteGenerateProps[3]="test.randomtextwrite.min_words_value"
	randomTextWriteGenerateProps[4]="test.randomtextwrite.max_words_value"

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
	
	confFilesHeader="<?xml version=\"1.0\"?>\n<?xml-stylesheet type=\"text/xsl\" href=\"configuration.xsl\"?>\n<configuration>"
	executionPrefix="bin/hadoop jar"
	bashScriptsHeadline="#!/bin/sh"
	testDirPrefix="test_"

	isSnappyExist=0
	isLZOExist=0
	maxSlaves=0
	addParamsTotalCount=3
	testsCount=0
	lastTeragenParam=-1
	lastRandonWriteParam=-1
	lastRandonTextWriteParam=-1
	digitsCount=2 # that means thet the execution folders will contains 2 digits number. 2 -> 02 for instance
	errorDesc=""

		# creating a file with the general exports of this session
	generalDir=testsFolderDir"/general.sh"
	#testLinkRearrange=testsFolderDir"/rearrangeDirsByTestLink.sh"
	exportsFile="exports.sh"

	system("echo '"bashScriptsHeadline "' > " generalDir)
	#system("echo '"bashScriptsHeadline "' > " testLinkRearrange)
}

($1 ~ /^#/){
	tmpProp=substr($1,2,length($1)-1)
	tmpVal=$2
	gsub(commaDelimitedPropsDelimiter,FS,tmpVal)
	generalParams[tmpProp]=$2		# for use in this script
	print "export csv" tmpProp "='" tmpVal "'" >> generalDir	# for use in runTest.sh
}

($1 ~ /DEFAULT(|S)/){
		# cleanning execParams for the next test	
	split("", defaults)
	
	for (i in headers)
		defaults[i]= $i	
}

($1 ~ /HEADERS/ ){
	getHeadersAndProperties()
	availableSlavesCount=buildSlavesFiles(-1,"",testsFolderDir)
}

($1 !~ /^#/) && ($1 !~ /HEADERS/) && ($1 !~ /DEFAULT(|S)/) && (match($0, "[^(\r|\n|,)]") > 0){ # \r is kind of line break character, like \n. \r is planted at the end of the record, $0. the purpuse of this match function is to avoid rows of commas (only), which can be part of csv file  
	if (($2 == 0) || (($2 == "") && (defaults[samplesHeaderPlace] == 0))) # if this row is not for execution
		next

	# ELSE:
	restartFlag=0
	
	getDefaultsIfNeeded()	# taking inputs from the DEFAULT line if neccesary 

	if (execParams["slaves"] == 0)
		next
	
	testsCount++
		# Creating the folder and exports file for the execution	
	testCountFormatted=formatNumber(testsCount,digitsCount)
	dirName=testDirPrefix testCountFormatted
	if ($1 ~ /[[:space:]]*/)
		dirName=dirName "-" $1
	execDir=testsFolderDir "/" dirName
	system("mkdir " execDir " ; echo '"bashScriptsHeadline "' > "execDir"/"exportsFile)
	print "export EXEC_NAME='" $1 "'" >> execDir"/"exportsFile

	if (execParams["TestLink_ID"] == "")
		testLinkID=lastTestLinkID
	else
		testLinkID=execParams["TestLink_ID"]
	#print "mkdir " testLinkID "; mv " dirName " testLinkID >> testLinkRearrange
	
		# finding the maximun amount of slaves in the tests
	if (execParams["slaves"] > availableSlavesCount)
		execParams["slaves"]=availableSlavesCount
		
	if (execParams["slaves"] > maxSlaves)
		maxSlaves=execParams["slaves"]

		# managing special properties
	manageCommaDelimitedProps(commaDelimitedProps)
	manageMinusPrefixProps(minusPrefixProps)
	manageBooleanValueProps(booleanValueProps)
	manageCreatingDirProps(creatingDirProps)
	
	if (execParams["program"]~/wordcount/)
	{
		randomTextWriteDParams=manageRandomTextWriteGenerateProps(randomTextWriteGenerateProps)
		print "export CMD_RANDOM_TEXT_WRITE_PARAMS='" randomTextWriteDParams "'" >> execDir "/" exportsFile
	}
	else if (execParams["program"]~/sort/)
	{
		randomWriteDParams=manageRandomWriteGenerateProps(randomWriteGenerateProps)
		print "export CMD_RANDOM_WRITE_PARAMS='" randomWriteDParams "'" >> execDir "/" exportsFile
	}
	
		# managing the parameters for the execution
	#confParams="\n"
	confParams=""
	TestDFSIOParams=""
	for (i in CMDprops)
	{
		propName=CMDprops[i]
		propValue=execParams[headers[i]]
		if (propValue != "")
		{
			if (valueInDict(propName,endingProps) == 1)
			{
				if (propName == endTypeFlag)
					TestDFSIOParams = TestDFSIOParams "-" propValue " "
				else
					TestDFSIOParams = TestDFSIOParams "-" propName " " propValue " "
			}
			else
				confParams = confParams "-D" propName "=" propValue " "
			
			if (match(propValue, /com.hadoop.compression.lzo.LzoCodec/) ==1)
				isLZOExist=1
			if (match(propValue, /org.apache.hadoop.io.compress.SnappyCodec/) == 1)
				isSnappyExist=1
		}
	}

	print "export CMD_PREFIX='" executionPrefix "'" >> execDir "/" exportsFile
	print "export CMD_JAR='" execParams["jar_dir"] "'" >> execDir "/" exportsFile
	print "export CMD_PROGRAM='" execParams["program"] "'" >> execDir "/" exportsFile
	print "export CMD_D_PARAMS='" confParams "'" >> execDir "/" exportsFile
	print "export CMD_TEST_DFSIO_PARAMS='" TestDFSIOParams "'" >> execDir "/" exportsFile
	
		# checking if there is a need to start/restart hadoop
		
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

		# saving parameters from the last execution, before starting new one
	lastSlavesCount = execParams["slaves"]	
	lastTestLinkID=execParams["TestLink_ID"]	
		
		# cleanning execParams for the next test	
	split("", execParams)
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
	else {
		print "export LZO=0" >> generalDir
		print "export COMPRESSION=0" >> generalDir
	}
	if ( isSnappyExist==1 ){
		print "export SNAPPY=1"  >> generalDir
		print "export COMPRESSION=1" >> generalDir
	}
	else{
		print "export SNAPPY=0"  >> generalDir
		print "export COMPRESSION=0" >> generalDir
	}

	dirsForCreationList=""
	for (i in dirsForCreation)
		dirsForCreationList = dirsForCreationList " " i
	print "export DIRS_TO_CREATE='" dirsForCreationList  "'"  >> generalDir
	
	print "export RELEVANT_SLAVES_BY_SPACES='" relevantSlavesSpace "'" >> generalDir
	print "export RELEVANT_SLAVES_BY_COMMAS='" relevantSlavesComma "'" >> generalDir
	print "export TESTS_COUNT=" testsCount >> generalDir
	print "export DEFAULT_RES_SERVER='" generalParams[glbMasters]  "'"  >> generalDir
	
	print "export ERRORS='" errorDesc "'" >> generalDir
	print errorDesc
}
