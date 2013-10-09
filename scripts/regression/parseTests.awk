#!/bin/awk -f

function round(x)
{
	ival = int(x)    # integer part, int() truncates

	# see if fractional part
	if (ival == x)   # no fraction
		return ival   # ensure no decimals

	if (x < 0)
	{
		aval = -x     # absolute value
		ival = int(aval)
		fraction = aval - ival
		if (fraction >= .5)
			return int(x) - 1   # -2.5 --> -3
		else
			return int(x)       # -2.3 --> -2
	} 
	else
	{
		fraction = x - ival
		if (fraction >= .5)
			return ival + 1
		else
			return ival
	}
}

function getHeadersAndProperties()
{
		# cleanning the arrays	
	split("", headers)
	split("", DMprops)
	split("", DMfiles)
	split("", CMDprops)
	split("", allProps)
	split("", envParams)
	split("", preReqProps)
	
	i=testDetailsStartIndex
	confParamsFlag=0
	while ($i !~ /PARAMS_END/) # the last field by convantion is the sentinel. thats why we not use i<=NF
	{
		ind=index($i,daemonsParamsIndicator)
		preInd=index($i,preReqIndicator)
		if (ind > 0)	# in case of daemon parameter
		{
			DMprops[i]=substr($i,1,ind-1)	# gets the daemon-property
			DMfiles[i]= substr($i,ind+1,length($i)+1-ind)	# gets the daemon-property correct configuration file
			headers[i]=DMprops[i]
			allProps[i]=DMprops[i]
		}
		else if (preInd > 0) # in case of preReq parameter
		{
			preReqProps[i]=substr($i,1,preInd-1)
			headers[i]=preReqProps[i]
		}
		else if (confParamsFlag) # there is no convention differance between non-daemon parameters and environment parameters (input/output dir etc.. so flag is needed to distinguish between them
		{
			CMDprops[i]=$i
			allProps[i]=CMDprops[i]
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
	for (i in defaults)
	{
		if (($i == ""))
			execParams[headers[i]]=defaults[i]
		else if ($i != emptyFieldFlag)
			execParams[headers[i]]=$i
	}
}

function manageLog4jPropsProps(logProps)
{
	ret=""
	for (i in logProps)
		ret=ret logProps[i] "=" execParams[i] " "
		
	return ret
}

function manageCommaDelimitedProps(commaProps)
{
	for (i in commaProps)
		gsub(commaDelimitedPropsDelimiter,FS,execParams[commaProps[i]])
}

function manageCreatingDirProps(masterDirProps, slaveDirProps)
{
	for (i in masterDirProps)
	{
		split(execParams[masterDirProps[i]], tmpDirs, FS)
		for (j in tmpDirs)
			dirsForMaster[tmpDirs[j]]="stam"
	}
	
	for (i in slaveDirProps)
	{
		split(execParams[slaveDirProps[i]], tmpDirs, FS)
		for (j in tmpDirs)
			dirsForSlaves[tmpDirs[j]]="stam"
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

function replaceMarksInAllProps()
{
	for (mark in marks)
	{
		for (prop in allProps)
		{
			if (index(execParams[allProps[prop]],masterMark))
				sub(marks[mark],master,execParams[allProps[prop]])
		}
	}
}

function formatNumber(num,digits)
{
	# right now supporting only digits=2
	numLen=length(num)
	if (numLen == 1)
		return "0" num
	return num
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

function manageBooleanValueProps(booleanProps)
{
	for (i in booleanProps)
	{
		if (execParams[booleanProps[i]]=="FALSE")
			execParams[booleanProps[i]]="false"
		else if (execParams[booleanProps[i]]=="TRUE")
			execParams[booleanProps[i]]="true"
		else if ((execParams[booleanProps[i]]!="true") && (execParams[booleanProps[i]]!="false") && (execParams[booleanProps[i]]!~/[[:space:]]*/))
			errorDesc = errorDesc "error in test #" $totalTestsCount " - wrong input at " booleanProps[i] "\n"		
	}
}

function makeListBySeperators(exportNameBeginning,dirsDict,dirLists)
{
	if (dirLists == "")
	{
		for (i in dirsDict)
			dirLists = dirLists " " i
	}
	print "export " exportNameBeginning "_BY_SPACES='" dirLists  "'"  >> setupsFile
	listByCommas=dirLists
	gsub(/[[:space:]]+/,",",listByCommas)
	print "export " exportNameBeginning "_BY_COMMAS='" listByCommas "'" >> setupsFile
	
	return dirLists
}

function buildSlavesFiles(pSlavesCount,pInterface,pDir)
{
	currentSlaves=""
	totalSlaves=split(slavesBySpaces,slaves,slavesDelimiter)
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

function buildPreReqFile()
{
	preReqFile=execDir"/"preReqFileName
	system("echo '"bashScriptsHeadline "' > " preReqFile)
	for (i in preReqProps)
	{
		print "export " headers[i] "='" execParams[headers[i]] "'" >> preReqFile 
	}
}

function exportMenager()
{	
	manageAddParams()
	
	for (exportName in slavesDirsProps)
	{
		tmpValue = execParams[slavesDirsProps[exportName]]
		gsub(FS," ",tmpValue)
		print "export " exportName "_BY_SPACES='" tmpValue "'" >> exportsFile
		tmpValue = execParams[slavesDirsProps[exportName]]
		gsub(FS,",",tmpValue)
		print "export " exportName "_BY_COMMAS='" tmpValue "'" >> exportsFile
	}
	
	print "export PRE_REQ_TEST_FLAGS='-" execParams["pre_req_flags"] "'" >> exportsFile # this minus is to avoid input of "-" in the csv file
	print "export PROGRAM='"execParams["program"] "'" >> exportsFile 
	print "export NSAMPLES="execParams["samples"] >> exportsFile
	print "export SLAVES_COUNT="execParams["slaves"] >> exportsFile
	print "export IB_MESSAGE_SIZE="execParams["ib_message"] >> exportsFile 
	print "export NR_FILES="execParams["nrFiles"] >> exportsFile
	print "export RDMA_BUF_SIZE="execParams["mapred.rdma.buf.size"] >> exportsFile
	print "export RDMA_BUF_SIZE_MIN="execParams["mapred.rdma.buf.size.min"] >> exportsFile
	print "export TEST_IDS="execParams["test_IDs"] >> exportsFile

	if (execParams["compression"] == emptyDefaultFlag)
	{
		print "export COMPRESSION_TEST_LEVEL=''" >> exportsFile
	}
	else
	{
		print "export COMPRESSION_TEST_LEVEL='"compressionDParams "'" >> exportsFile
	}
	
	manageSpecialHadoopExports()
}

function manageAddParams()
{
	teragen=0
	teraval=0
	randomWrite=0
	randomTextWrite=0
	forceGeneratingData=0
	traceJob=0
	cacheFlushing=0
	deleteData=0
	forceDfsFormat=0
	
	split(execParams["add_params"],params,/[[:space:]]+/)
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
		else if (params[p] == forceGeneratingDataFlag)
			forceGeneratingData=1
		else if (params[p] == traceJobFlag)
			traceJob=1	
		else if (params[p] == cacheFlushingFlag)
			cacheFlushing=1
		else if (params[p] == deleteDataFlag)
			deleteData=1
		else if (params[p] == restartHadoopIndicator)
			restartHadoopFlag=1	
		else if (params[p] == forceDfsFormatFlag)
			forceDfsFormat=1				
	}	

	print "export TERAVALIDATE=" teraval >> exportsFile		
	print "export TERAGEN=" teragen >> exportsFile
	print "export RANDOM_WRITE=" randomWrite >> exportsFile
	print "export RANDOM_TEXT_WRITE=" randomTextWrite >> exportsFile
	print "export FORCE_DATA_GENERATION=" forceGeneratingData >> exportsFile
	print "export TRACE_JOB_FLAG="traceJob >> exportsFile
	print "export CACHE_FLUHSING=" cacheFlushing >> exportsFile	
	print "export DELETE_DATA=" deleteData >> exportsFile	
	print "export FORCE_DFS_FORMAT=" forceDfsFormat >> exportsFile
	
	if ((execParams["program"]~/terasort/) || (execParams["program"]~/sort/) || (execParams["program"]~/wordcount/))
		print "export DATA_SET="params[1] >> exportsFile
	else if (execParams["program"]~/pi/)
	{
		len=split(execParams["add_params"],params,/[[:space:]]+/)
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
		print "export PI_MAPPERS=" piMappers >> exportsFile
		print "export PI_SAMPLES=" piSamples >> exportsFile
	}
	else if (execParams["program"]~/TestDFSIO/)
	{
		print "" # wating for some logic...
	}
	
		# cleanning the array	
	split("", params)
}

function manageSpecialHadoopExports()
{
	dfsDirsList=""
	if (yarnFlag == 1)
	{	
		#print "export JOBHISTORIES_DIR="execParams["mapreduce.jobtracker.jobhistory.location"] >> exportsFile
		print "export NODEMANAGER_LOG_DIR="execParams["yarn.nodemanager.log-dirs"] >> exportsFile # Added by Elad to support Hadoop 2 and 3 log dirs
		
		print "export MAX_MAPPERS="execParams["mapreduce.tasktracker.map.tasks.maximum"] >> exportsFile
		print "export MAX_REDUCERS="execParams["mapreduce.tasktracker.reduce.tasks.maximum"] >> exportsFile
		print "export DESIRED_MAPPERS="execParams["mapreduce.job.maps"] >> exportsFile
		print "export DESIRED_REDUCERS="execParams["mapreduce.job.reduces"] >> exportsFile

		diskCount=split(execParams["dfs.datanode.data.dir"],srak,",")
		print "export DISKS_COUNT="diskCount >> exportsFile
		
		if ((execParams[udaConsumerProp] == udaConsumerValue) && (execParams[udaConsumerProp2] == udaProviderValue2))
			print "export SHUFFLE_CONSUMER=1" >> exportsFile
		else 
			print "export SHUFFLE_CONSUMER=0" >> exportsFile
			
		tmpValue = execParams["yarn.nodemanager.log-dirs"]
		gsub(FS," ",tmpValue)
		dfsDirsList=dfsDirsList " " tmpValue
	}
	else
	{
		print "export MAX_MAPPERS="execParams["mapred.tasktracker.map.tasks.maximum"] >> exportsFile
		print "export MAX_REDUCERS="execParams["mapred.tasktracker.reduce.tasks.maximum"] >> exportsFile
		print "export DESIRED_MAPPERS="execParams["mapred.map.tasks"] >> exportsFile
		print "export DESIRED_REDUCERS="execParams["mapred.reduce.tasks"] >> exportsFile
				
		diskCount=split(execParams["dfs.data.dir"],srak,",")
		print "export DISKS_COUNT="diskCount >> exportsFile
		
		if (execParams[udaConsumerProp] == udaConsumerValue)
			print "export SHUFFLE_CONSUMER=1" >> exportsFile
		else 
			print "export SHUFFLE_CONSUMER=0" >> exportsFile

		if (execParams[udaProviderProp] == udaProviderValue)
			print "export SHUFFLE_PROVIDER=1" >> exportsFile
		else
			print "export SHUFFLE_PROVIDER=0" >> exportsFile
	}

	if (cdhFlag == 1)
	{
		split(execParams["mapred.local.dir"], temp, FS)
		for (i in temp)
		{
			dfsDirsList=dfsDirsList " " temp[i] "/" userlogsRelativeDir
		}
	}
	print "export DFS_DIR_FOR_LOGS_COLLECTION='" dfsDirsList "'" >> exportsFile
}

function restartHadoopHandler()
{
		# cleanning the array	
	split("", currentDMs)

	for (j in DMprops)
		currentDMs[j] = execParams[headers[j]]

	interfaceToPlant=""
	if (interface ~ /[A-Za-z0-9_]+/)
		interfaceToPlant= "-" interface
		
	execSlaves=buildSlavesFiles(execParams["slaves"],interfaceToPlant,execDir)
	buildMastersFile(master)
	buildConfigurationFiles()
}

function resetSetupHandler()
{
	setupCountFormatted=formatNumber(setupsCounter,digitsCount)
	setupName=setupPrefix setupCountFormatted
	allTestsSetupsNames=allTestsSetupsNames" "setupName
	setupDir=confsFolderDir "/"setupName
		
	restartHadoopHandler()
	system("mkdir " setupDir " ; mv " execDir " " setupDir)

	generalFile=setupDir"/"generalFileName
	system("echo '"bashScriptsHeadline "' > " generalFile)
	
	setSetupExports()
	setupsCounter++
}

function setSetupExports()
{	
	if (maxSlaves > 0)
	{
		split(slavesBySpaces, temp, slavesDelimiter)
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
	print "export RELEVANT_SLAVES_BY_SPACES='" relevantSlavesSpace "'" >> generalFile
	print "export RELEVANT_SLAVES_BY_COMMAS='" relevantSlavesComma "'" >> generalFile
	relevantMachinesSpace=master " " relevantSlavesSpace
	relevantMachinesComma=master "," relevantSlavesComma
	print "export RELEVANT_MACHINES_BY_SPACES='" relevantMachinesSpace "'" >> generalFile
	print "export RELEVANT_MACHINES_BY_COMMAS='" relevantMachinesComma "'" >> generalFile
	print "export LOGGER_PARAMS_AND_VALS='" log4jParamsAndVals "'" >> generalFile
	
	#if ("log_num_mtt" in execParams)
	print "export LOG_NUM_MTT="execParams["log_num_mtt"] >> generalFile
	#if ("log_mtts_per_seg" in execParams)
	print "export LOG_MTTS_PER_SEG="execParams["log_mtts_per_seg"] >> generalFile
	
	print "export SETUP_TESTS_COUNT=" setupTestsCount >> generalFile
	setupTestsCount=0
}

function checkRandomValues()
{
	for (i in execParams)
	{
		paramsCount=split(execParams[i],tmp,/[[:space:]]+/)
		if ((paramsCount != 0) && (tmp[1] == randomIndicator))
		{ 
			aLim=tmp[2]
			bLim=tmp[3]
			quant=tmp[4]
			step=(bLim-aLim)*rand() / quant
			step=round(step)
			execParams[i]=aLim + step*quant
			print "THE PROP IS: " i " VALUE: "execParams[i] 
		}
	}
}

BEGIN{
	FS=","
	
	srand(seed);
	
	testDescriptionIndex=1
	testDetailsStartIndex=2
	samplesHeaderPlace=3
	
	daemonsParamsIndicator="@"
	preReqIndicator="#"
	
	teravalFlag="v"
	teragenFlag="g"
	randomWriteFlag="w"
	randomTextWriteFlag="t"
	cacheFlushingFlag="c"
	forceGeneratingDataFlag="f"
	traceJobFlag="j"
	deleteDataFlag="d"
	forceDfsFormatFlag="F"
	restartHadoopIndicator="r"
	emptyFieldFlag="x"
	endTypeFlag="end_flag"
	randomIndicator="RAND"
	emptyDefaultFlag="NONE"

	masterMark="{MASTER}"
	marks[1]="{MASTER}"
	
		# the names of the configuration files
	confFiles["mapred"]="mapred-site.xml"
	confFiles["hdfs"]="hdfs-site.xml"
	confFiles["core"]="core-site.xml"
	confFiles["yarn"]="yarn-site.xml"
	
	log4jProps["provider_log_level"]="log4j.logger.org.apache.hadoop.mapred.ShuffleProviderPlugin"
	log4jProps["consumer_log_level"]="log4j.logger.org.apache.hadoop.mapred.ShuffleConsumerPlugin"
	log4jProps["log4j.logger.org.apache.hadoop.mapred"]="log4j.logger.org.apache.hadoop.mapred"
	log4jProps["log4j.logger.org.apache.hadoop.mapred.ReduceTask"]="log4j.logger.org.apache.hadoop.mapred.ReduceTask"
	log4jProps["log4j.logger.org.apache.hadoop.mapred.ShuffleConsumerPlugin"]="log4j.logger.org.apache.hadoop.mapred.ShuffleConsumerPlugin"
	log4jProps["log4j.logger.org.apache.hadoop.mapreduce.task.reduce.Shuffle"]="log4j.logger.org.apache.hadoop.mapreduce.task.reduce.Shuffle"
	log4jProps["log4j.logger.org.apache.hadoop.mapred.TaskTracker"]="log4j.logger.org.apache.hadoop.mapred.TaskTracker"
	log4jProps["log4j.logger.org.apache.hadoop.mapred.UdaPluginSH"]="log4j.logger.org.apache.hadoop.mapred.UdaPluginSH"
	log4jProps["log4j.logger.com.mellanox.hadoop.mapred.UdaShuffleHandler"]="log4j.logger.com.mellanox.hadoop.mapred.UdaShuffleHandler"

		# properties with can have multiple values, seperating bt commas. because the awk is works with Comma Seperated file, those parameters should be seperating by other delimiter
	commaDelimitedPropsDelimiter=";"
	commaDelimitedProps[1]="dfs.data.dir"
	commaDelimitedProps[2]="dfs.name.dir"
	commaDelimitedProps[3]="hadoop.tmp.dir"
	commaDelimitedProps[4]="mapred.local.dir"
	commaDelimitedProps[5]="dfs.datanode.data.dir"
	commaDelimitedProps[6]="dfs.namenode.name.dir"
	commaDelimitedProps[7]="mapreduce.shuffle.provider.plugin.classes"
	commaDelimitedProps[8]="mapreduce.cluster.local.dir"
	commaDelimitedProps[9]="yarn.nodemanager.aux-services"
	commaDelimitedProps[10]="yarn.nodemanager.application-listeners"
	commaDelimitedProps[11]="yarn.nodemanager.log-dirs"
	commaDelimitedProps[12]="yarn.nodemanager.local-dirs"

	slavesDelimiter=" "
	dirPropsDelimiter=commaDelimitedPropsDelimiter
	slavesDirsProps["DFS_DATA_DIR"]="dfs.data.dir"
	slavesDirsProps["HADOOP_TMP_DIR"]="hadoop.tmp.dir"
	slavesDirsProps["MAPRED_LOCAL_DIR"]="mapred.local.dir"
	slavesDirsProps["DFS_DATANODE_DATA_DIR"]="dfs.datanode.data.dir"
	slavesDirsProps["MAPREDUCE_CLUSTER_LOCAL_DIR"]="mapreduce.cluster.local.dir"
	slavesDirsProps["YARN_NODEMANAGER_LOGDIRS"]="yarn.nodemanager.log-dirs"
	slavesDirsProps["YARN_NODEMANAGER_LOCALDIRS"]="yarn.nodemanager.local-dirs"

	masterDirsProps["DFS_NAME_DIR"]="dfs.name.dir"
	masterDirsProps["DFS_NAMENODE_NAME_DIR"]="dfs.namenode.name.dir"	
	masterDirsProps["HADOOP_TMP_DIR"]="hadoop.tmp.dir"

	formatDfsProps["dfs.data.dir"]=0
	formatDfsProps["dfs.name.dir"]=0
	formatDfsProps["hadoop.tmp.dir"]=0
	formatDfsProps["mapred.local.dir"]=0
	
	minusPrefixProps[1]="mapred.map.child.java.opts" 	# for hadoop 1.x
	minusPrefixProps[2]="mapred.reduce.child.java.opts" # for hadoop 1.x
	minusPrefixProps[3]="mapred.child.java.opts"		# for hadoop 0.20.2
    minusPrefixProps[4]="mapreduce.map.java.opts"       # for hadoop 2                                                             
    minusPrefixProps[5]="mapreduce.reduce.java.opts"    # for hadoop 2                                                     
	
	booleanValueProps[1]="mapred.map.tasks.speculative.execution"
	booleanValueProps[2]="mapred.reduce.tasks.speculative.execution"
	booleanValueProps[3]="keep.failed.task.files"
	booleanValueProps[4]="dfs.permissions"

	randomWriteGenerateProps[1]="test.randomwrite.min_key"
	randomWriteGenerateProps[2]="test.randomwrite.max_key"
	randomWriteGenerateProps[3]="test.randomwrite.min_value"
	randomWriteGenerateProps[4]="test.randomwrite.max_value"
	randomWriteGenerateProps[5]="mapreduce.randomwriter.minkey"
	randomWriteGenerateProps[6]="mapreduce.randomwriter.maxkey"
	randomWriteGenerateProps[7]="mapreduce.randomwriter.minvalue"
	randomWriteGenerateProps[8]="mapreduce.randomwriter.maxvalue"
	
	randomTextWriteGenerateProps[1]="test.randomtextwrite.min_words_key"
	randomTextWriteGenerateProps[2]="test.randomtextwrite.max_words_key"
	randomTextWriteGenerateProps[3]="test.randomtextwrite.min_words_value"
	randomTextWriteGenerateProps[4]="test.randomtextwrite.max_words_value"
	randomTextWriteGenerateProps[5]="mapreduce.randomtextwriter.minwordskey"
	randomTextWriteGenerateProps[6]="mapreduce.randomtextwriter.maxwordskey"
	randomTextWriteGenerateProps[7]="mapreduce.randomtextwriter.minwordsvalue"
	randomTextWriteGenerateProps[8]="mapreduce.randomtextwriter.maxwordsvalue"
	
	endingProps[1]="nrFiles"
	endingProps[2]="fileSize"
	endingProps[3]=endTypeFlag
	
	udaEnableProps[1]="mapreduce.job.reduce.shuffle.consumer.plugin.class"
	udaEnableProps[2]="mapred.reducetask.shuffle.consumer.plugin"

	#masterMachineProps[1]="mapred.job.tracker"
	#masterMachineProps[2]="fs.default.name"
	
	piMappersDefault=10
	piSamplesDefault=100
	
	confFilesHeader="<?xml version=\"1.0\"?>\n<?xml-stylesheet type=\"text/xsl\" href=\"configuration.xsl\"?>\n<configuration>"
	bashScriptsHeadline="#!/bin/sh"
	setupsFileName="allSetupsExports.sh"
	generalFileName="general.sh"
	exportsFileName="exports.sh"
	preReqFileName="preReqTest.sh"
	
	allTestsSetupsNames=""
	resetSetupFlag=1
	maxSlaves=0
	totalTestsCount=0
	setupTestsCount=0
	lastLogNumMttCount=-1
	lastLogMttsPerSegCount=-1
	digitsCount=2 # that means thet the execution folders will contains 2 digits number. 2 -> 02 for instance
	setupsCounter=1
	errorDesc=""

		# creating a file with the general exports of this session
	setupsFile=confsFolderDir"/"setupsFileName
	system("echo '"bashScriptsHeadline "' > " setupsFile)

	#testLinkRearrange=confsFolderDir"/rearrangeDirsByTestLink.sh"
	#system("echo '"bashScriptsHeadline "' > " testLinkRearrange)
}

($1 ~ /DEFAULT(|S)/){
		# cleanning execParams for the next test	
	split("", defaults)
	
	for (i in headers)
		defaults[i]= $i	
}

($1 ~ /HEADERS/ ){
	getHeadersAndProperties()
	availableSlavesCount=buildSlavesFiles(-1,"",confsFolderDir)
}

($1 !~ /HEADERS/) && ($1 !~ /DEFAULT(|S)/) && (match($0, "[^(\r|\n|,)]") > 0){ # \r is kind of line break character, like \n. \r is planted at the end of the record, $0. the purpuse of this match function is to avoid rows of commas (only), which can be part of csv file  
	if (($samplesHeaderPlace == 0) || (($samplesHeaderPlace == "") && (defaults[samplesHeaderPlace] == 0))) # if this row is not for execution
		next
	
	# ELSE:
	restartHadoopFlag=0
	
	getDefaultsIfNeeded()	# taking inputs from the DEFAULT line if neccesary 
	checkRandomValues()
	
	if (execParams["slaves"] == 0)
		next
	
	totalTestsCount++
	setupTestsCount++

		# Creating the folder and exports file for the execution	
	testCountFormatted=formatNumber(totalTestsCount,digitsCount)
	dirName=testDirPrefix testCountFormatted
	if ($testDescriptionIndex ~ /[[:space:]]*/)
		dirName=dirName "-" $testDescriptionIndex
	execDir=confsFolderDir "/" dirName
	exportsFile=execDir"/"exportsFileName
	system("mkdir " execDir " ; echo '"bashScriptsHeadline "' > " exportsFile)
	print "export TEST_NAME='" $testDescriptionIndex "'" >> exportsFile
	arrTestNames[$testDescriptionIndex]=totalTestsCount

	#if (execParams["TestLink_ID"] == "")
	#	testLinkID=lastTestLinkID
	#else
	#	testLinkID=execParams["TestLink_ID"]
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
	manageCreatingDirProps(masterDirsProps, slavesDirsProps)
	replaceMarksInAllProps()

	buildPreReqFile()	

	log4jParamsAndVals=manageLog4jPropsProps(log4jProps)
	
		# managing the parameters for the execution
	udaCliParams=""
	cliParamsWithoutUda=""
	TestDFSIOParams=""
	randomTextWriteDParams=""
	randomWriteDParams=""
	
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
			else if (valueInDict(propName,udaEnableProps) == 1)
			{
				udaCliParams = udaCliParams "-D" propName "=" propValue " "	
			}
			else if (valueInDict(propName,randomTextWriteGenerateProps) == 1)
			{ 
				randomTextWriteDParams = randomTextWriteDParams "-D" propName "=" propValue " "	
			}
			else if (valueInDict(propName,randomWriteGenerateProps) == 1)
			{
				randomWriteDParams = randomWriteDParams "-D" propName "=" propValue " "	
			}
			else
			{
				cliParamsWithoutUda = cliParamsWithoutUda "-D" propName "=" propValue " "	
			}
		}
	}

	print "export CMD_JAR='" execParams["jar_dir"] "'" >> exportsFile
	print "export CMD_PROGRAM='" execParams["program"] "'" >> exportsFile
	print "export CMD_D_PARAMS='" cliParamsWithoutUda "'" >> exportsFile
	print "export CMD_TEST_DFSIO_PARAMS='" TestDFSIOParams "'" >> exportsFile
	print "export CMD_RANDOM_TEXT_WRITE_PARAMS='" randomTextWriteDParams "'" >> exportsFile
	print "export CMD_RANDOM_WRITE_PARAMS='" randomWriteDParams "'" >> exportsFile
	
	if (disableUda == 1)
	{
		print "export CMD_UDA_ENABLE=''" >> exportsFile
	}
	else
	{
		print "export CMD_UDA_ENABLE='" udaCliParams "'" >> exportsFile
	}
	
	if (totalTestsCount==1)
		print "export FIRST_STARTUP=1" >> exportsFile
	else
		print "export FIRST_STARTUP=0" >> exportsFile

		# checking if there is a need to start/restart hadoop	
	if (lastSlavesCount != execParams["slaves"])
		restartHadoopFlag=1
	else # checking if there is changes is daemon-parameters since the last execution
	{
		for (i in DMprops)
			if (execParams[headers[i]] != currentDMs[i]){
				restartHadoopFlag=1
				break
			}
	}

		# checking the criterias of reseting the cluster's setup
	if ((lastLogNumMttCount != execParams["log_num_mtt"]) || (lastLogMttsPerSegCount != execParams["log_mtts_per_seg"])) # restarting setup because mtt
		resetSetupFlag=1
	if ((lastUdaLogLevel != execParams["uda_log_level"]) || (lastProviderLogLevel != execParams["provider_log_level"]) || (lastConsumerLogLevel != execParams["consumer_log_level"])) # restarting setup because uda's log-level
		resetSetupFlag=1
	
	formatDfs=0
	for (i in formatDfsProps)
	{
		if (formatDfsProps[i] != execParams[i])
		{
			formatDfsProps[i]=execParams[i]
			formatDfs=1
		}
	}
	print "export FORMAT_DFS=" formatDfs >> exportsFile
	
	exportMenager()
	if (resetSetupFlag==1)
	{
		print "export RESTART_HADOOP=1" >> exportsFile
		resetSetupHandler()
	}
	else
	{
		if (restartHadoopFlag==1)
		{
			print "export RESTART_HADOOP=1" >> exportsFile
			restartHadoopHandler()
		}
		else
			print "export RESTART_HADOOP=0" >> exportsFile
			
		system("mv " execDir " " setupDir)
	}
		
	# check for errors
	#if (execParams["mapred.tasktracker.map.tasks.maximum"] < execParams["mapred.tasktracker.reduce.tasks.maximum"])
	#	errorDesc = errorDesc "error in " $1 " - more reducers-slots than mappers-slots \n"

		# saving parameters from the last execution, before starting new one
	lastSlavesCount = execParams["slaves"]
	lastLogNumMttCount = execParams["log_num_mtt"]
	lastLogMttsPerSegCount = execParams["log_mtts_per_seg"]
	lastUdaLogLevel = execParams["uda_log_level"]
	lastProviderLogLevel = execParams["provider_log_level"]
	lastConsumerLogLevel = execParams["consumer_log_level"]
	#lastTestLinkID=execParams["TestLink_ID"]	
		
		# cleanning execParams for the next test	
	split("", execParams)
	
	resetSetupFlag=0
}

END{
	print "export TOTAL_TESTS_COUNT=" totalTestsCount >> setupsFile
	print "export SETUPS_COUNT=" setupsCounter >> setupsFile
	print "export ALL_TESTS_SETUPS_NAMES='" allTestsSetupsNames "'">> setupsFile
	
	mastersDfsDirsList=makeListBySeperators("MASTER_DFS_DIRS", dirsForMaster, "")
	slavesDfsDirsList=makeListBySeperators("SLAVES_DFS_DIRS" ,dirsForSlaves, "")
	allDfsDirsList=mastersDfsDirsList " " slavesDfsDirsList
	slavesDfsDirsList=makeListBySeperators("ALL_DFS_DIRS", "", allDfsDirsList)
	
	allTestsNames=""
	for (i=1; i<=totalTestsCount; i++)
		allTestsNamesInverse[arrTestNames[test]]=0
	for (test in arrTestNames)
		allTestsNamesInverse[arrTestNames[test]]=test
	for (i=1; i<=totalTestsCount; i++)
		if (allTestsNamesInverse[i] != 0)
			allTestsNames=allTestsNames " " allTestsNamesInverse[i]
	print "export ALL_TESTS_NAMES='" allTestsNames "'"  >> setupsFile
	
	print "export TESTS_ERRORS='" errorDesc "'" >> setupsFile
	print errorDesc
}
