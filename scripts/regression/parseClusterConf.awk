#!/bin/awk -f

function getHeadersAndProperties()
{
		# cleanning the array	
	split("", headers)
	split("", preReqProps)

	i=1
	while ($i !~ /PARAMS_END/) # the last field by convantion is the sentinel. thats why we not use i<=NF
	{
		preInd=index($i,preReqIndicator)
		if (preInd > 0) # in case of preReq parameter
		{
			preReqProps[i]=substr($i,1,preInd-1)
			headers[i]=preReqProps[i]
		}
		else
		{
			headers[i]=$i
		}
		i++
	}
}

function getValues()
{
	for (i in headers)
		values[headers[i]]=$i
}

function formatNumber(num,digits)
{
	# right now supporting only digits=2
	numLen=length(num)
	if (numLen == 1)
		return "0" num
	return num
}

function manageFlags()
{
	build=0
	rpm=0
	unspreadConf=0
	disableUda=0
	
	split(values["flags"],params,/[[:space:]]*/)
	for (p in params)
	{
		if (params[p] == buildFlag)
			build=1
		if (params[p] == rpmFlag)
			rpm=1
		if (params[p] == unspreadConfFlag)
			unspreadConf=1
		if (params[p] == disableUdaFlag)
			disableUda=1
	}
	
	print "export BUILD_FLAG=" build >> envExports
	print "export RPM_FLAG=" rpm >> envExports
	print "export UNSPREAD_CONF_FLAG=" unspreadConf >> envExports	
	print "export DISABLE_UDA_FLAG=" disableUda >> envExports	
		
		# cleanning the array	
	split("", params)	
}

function buildPreReqFile()
{
	preReqFile=envDir"/"preReqFileName
	system("echo '"bashScriptsHeadline "' > " preReqFile)
	for (i in preReqProps)
	{
		print "export " headers[i] "='" values[headers[i]] "'" >> preReqFile 
	}
}

BEGIN{
	FS=","
	
	preReqIndicator="#"
	
	compressionCodecPropHadoop1="mapred.map.output.compression.codec"	
	compressionCodecPropYarn="mapreduce.map.output.compress.codec"
	compressionCodecValues["Snappy"]="org.apache.hadoop.io.compress.SnappyCodec"
	compressionCodecValues["BZip2"]="org.apache.hadoop.io.compress.BZip2Codec"
	compressionCodecValues["Gzip"]="org.apache.hadoop.io.compress.GzipCodec"
	compressionCodecValues["Lzo"]="com.hadoop.compression.lzo.LzoCodec"
	
	compressionEnablerPropHadoop1="mapred.compress.map.output"
	compressionEnablerPropYarn="mapreduce.map.output.compress"
	compressionEnablerValue="true"

	buildFlag="b"
	rpmFlag="r"
	unspreadConfFlag="u"
	disableUdaFlag="disableUDA"
	commaDelimitedPropsDelimiter=";"
	
	hadoopSpecialScripts["1"]="commandsOfHadoop1.sh"
	hadoopSpecialScripts["2"]="commandsOfHadoop2.sh"
	hadoopSpecialScripts["3"]="commandsOfHadoop2.sh" # got the same one as 2
	hadoopSpecialScripts["CDH"]="commandsOfHadoopCDH.sh"
	
	totalEnvs=0
	digitsCount=2 # that means thet the execution folders will contains 2 digits number. 2 -> 02 for instance
	errorDesc=""
	
	allEnvs=""
	
	bashScriptsHeadline="#!/bin/sh"
	generalEnvsExportsFile=sourcesDir"/generalEnvExports.sh"
	system("echo '"bashScriptsHeadline "' > " generalEnvsExportsFile)
}

($1 ~ /environment_name/){
	getHeadersAndProperties()
}

($1 !~ /environment_name/) && (match($0, "[^(\r|\n|,)]") > 0){ # \r is kind of line break character, like \n. \r is planted at the end of the record, $0. the purpuse of this match function is to avoid rows of commas (only), which can be part of csv file  
	if (($2 == 0) || ($2 == "")) # if this row is not for execution
		next

	# ELSE:
	totalEnvs++
	getValues()

	envName=values["environment_name"]
	
	envCountFormatted=formatNumber(totalEnvs,digitsCount)
	envFixedName=envDirPrefix envCountFormatted
	if ($envName ~ /[[:space:]]*/)
		envFixedName=envFixedName "-" envName
	allEnvs=allEnvs" "envFixedName
	
	envDir=baseDir"/"envFixedName
	envExports=envDir"/"envExportFileName
	system("mkdir " envDir " ; echo '"bashScriptsHeadline "' > " envExports)
	
	buildPreReqFile()
	system("echo '"bashScriptsHeadline "' > " envExports)
	print "export PRE_REQ_SETUP_FLAGS='-" values["pre_req_flags"] "'" >> envExports # this minus is to avoid input of "-" in the csv file
	
	print "export ENV_NAME='" envName "'" >> envExports
	print "export ENV_NUMBER='" totalEnvs "'" >> envExports 
	print "export ENV_FIXED_NAME='" envFixedName "'" >> envExports
	
	hadoopValue=values["hadoop"]
	print "export MY_HADOOP_HOME='" hadoopValue "'" >> envExports
	splitsCount=split(hadoopValue,tmp,"/")
	# to support case when the input ends with "/"
	len=length(hadoopValue)
	lastChar=substr(hadoopValue,len,1)
	if (lastChar == "/")
	{
		splitsCount--	
	}
	
	hadoopDirname=tmp[splitsCount]
	print "export HADOOP_DIRNAME='" hadoopDirname "'" >> envExports
	if (splitsCount == 1) # there are no slashes in this field
	{
		print "export CO_FLAG=1" >> envExports
	}
	else
	{
		print "export LOCAL_HADOOP_DIR='" hadoopValue "'" >> envExports
		print "export CO_FLAG=0" >> envExports
	}

	### parsing hadoopDirname from hadoop-x.y.z to x ###
	splitsCount=split(hadoopDirname,tmp,"-")
	splitsCount=split(tmp[2],tmp,".")
	hadoopType=tmp[1]
	print "export HADOOP_TYPE='" hadoopType "'" >> envExports
	
	if ((hadoopType == "1") || (hadoopType == "CDH"))
	{
		yarnFlag=0
		changeMachineNameFlag=0
	}
	else if ((hadoopType == "2") || (hadoopType == "3"))
	{
		yarnFlag=1
		changeMachineNameFlag=1
	}
	else
	{
		errorDesc=errorDesc  "unknown hadoop type (hadoop type = " hadoopType ")"
		next
	}

	print "export YARN_HADOOP_FLAG='" yarnFlag "'" >> envExports
	print "export CHANGE_MACHINE_NAME_FLAG='" changeMachineNameFlag "'" >> envExports
	print "export HADOOP_SPECIAL_SCRIPT_NAME='" hadoopSpecialScripts[hadoopType] "'" >> envExports
	
	print "export RPM_JAR='" values["rpm_jar"] "'" >> envExports
	udaPlaceValue=values["rpm_dir"]
	gitBranch=""
	slashesDevs=split(udaPlaceValue, slashes ,"/")
	dotsDev=split(udaPlaceValue, dots ,".")
	
	if (slashesDevs == 1) # there are no slashes in this field - the input is from repository
	{
		udaPlaceType = 1
		gitBranch = udaPlaceValue
	}
	else if (dots[dotsDev] == "rpm") # there are no slashes in this field - the input is built-rpm
		udaPlaceType = 0
	else # the input is local branch 
	{
		udaPlaceType = 2
		gitBranch = slashes[slashesDevs]
	}
	
	print "export UDA_PLACE_TYPE=" udaPlaceType >> envExports
	print "export UDA_PLACE_VALUE='" udaPlaceValue "'" >> envExports
	print "export GIT_BRANCH='" gitBranch "'" >> envExports
	
	print "export PATCH_NAME='" values["patch_name"] "'" >> envExports
	if (values["patch_name"] ~ /[A-Za-z0-9_]+/)
		print "export PATCH_FLAG=1" >> envExports
	else
		print "export PATCH_FLAG=0" >> envExports
			
	compressionType=values["compression"]
	compressionValueDParams=""
	if (compressionType ~ /[A-Za-z0-9_]+/)
	{
		compressionEnabler=""
		if (yarnFlag == 0)
		{
			compressionEnabler="-D"compressionEnablerPropHadoop1"="compressionEnablerValue
			finalCompressionCodecProp = compressionCodecPropHadoop1
		}
		else
		{
			compressionEnabler="-D"compressionEnablerPropYarn"="compressionEnablerValue
			finalCompressionCodecProp = compressionCodecPropYarn 
		}
		compressionValueDParams="-D" finalCompressionCodecProp "=" compressionCodecValues[compressionType] " " compressionEnabler
	}
	print "export COMPRESSION='" compressionType "'" >> envExports
	print "export COMPRESSION_D_PARAMETERS='" compressionValueDParams "'" >> envExports

	print "export HUGE_PAGES_COUNT='" values["huge_pages"] "'" >> envExports
	print "export TEST_CONF_FILE='" values["test_conf_file"] "'" >> envExports
	
	interface=values["interface"]
	master=values["master"]
	masterForXmls=master"-"interface
	print "export INTERFACE='" interface "'" >> envExports
	print "export MASTER='" master "'" >> envExports
	print "export MASTER_FOR_XMLS='" masterForXmls "'" >> envExports
	# till we'll decide about the RES_SERVER policy:
	print "export DEFAULT_RES_SERVER='" master  "'"  >> envExports
	print "export RES_SERVER='" master  "'"  >> envExports
	
	slaves=values["slaves"]
	slavesByCommas=slaves
	gsub(commaDelimitedPropsDelimiter,",",slavesByCommas)
	print "export SLAVES_BY_COMMAS='" slavesByCommas "'" >> envExports
	slavesBySpaces=slaves
	gsub(commaDelimitedPropsDelimiter," ",slavesBySpaces)
	print "export SLAVES_BY_SPACES='" slavesBySpaces "'" >> envExports
	split(slaves, envSlaves, commaDelimitedPropsDelimiter)
	for (slave in envSlaves)
		allSlaves[envSlaves[slave]]=envSlaves[slave]
	
	envMachinesBySpaces= master " " slavesBySpaces
	print "export ENV_MACHINES_BY_SPACES='" envMachinesBySpaces "'"  >> generalEnvsExportsFile
	envMachinesByCommas= master "," slavesByCommas
	print "export ENV_MACHINES_BY_COMMAS='" envMachinesByCommas "'"  >> generalEnvsExportsFile
	
	if (values["huge_pages"] ~ /[0-9]+/)
		print "export HUGE_PAGES_FLAG=1" >> envExports
	else
		print "export HUGE_PAGES_FLAG=0" >> envExports
	
	manageFlags()
}

END{
	print "export ENVS_COUNT=" totalEnvs >> generalEnvsExportsFile
	print "export ALL_ENVS='" allEnvs "'"  >> generalEnvsExportsFile
	
	allSlavesBySpaces=""
	allSlavesByCommas=""
	for (slave in allSlaves)
	{
		allSlavesBySpaces= slave " " allSlavesBySpaces
		allSlavesByCommas= slave "," allSlavesByCommas
	}
	print "export ALL_SLAVES_BY_SPACES='" allSlavesBySpaces "'"  >> generalEnvsExportsFile
	print "export ALL_SLAVES_BY_COMMAS='" allSlavesByCommas "'"  >> generalEnvsExportsFile
	
	allMachinesBySpaces= master " " allSlavesBySpaces
	allMachinesByCommas= master "," allSlavesByCommas
	print "export ALL_MACHINES_BY_SPACES='" allMachinesBySpaces "'"  >> generalEnvsExportsFile
	print "export ALL_MACHINES_BY_COMMAS='" allMachinesByCommas "'"  >> generalEnvsExportsFile
	
	#print "export ERRORS='" errorDesc "'" >> generalEnvsExportsFile
	#print errorDesc
}
