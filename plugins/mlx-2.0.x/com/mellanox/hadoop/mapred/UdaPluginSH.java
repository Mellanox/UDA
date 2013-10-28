/*
** Copyright (C) 2012 Auburn University
** Copyright (C) 2012 Mellanox Technologies
** 
** Licensed under the Apache License, Version 2.0 (the "License");
** you may not use this file except in compliance with the License.
** You may obtain a copy of the License at:
**  
** http://www.apache.org/licenses/LICENSE-2.0
** 
** Unless required by applicable law or agreed to in writing, software
** distributed under the License is distributed on an "AS IS" BASIS,
** WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, 
** either express or implied. See the License for the specific language 
** governing permissions and  limitations under the License.
**
**
*/
package com.mellanox.hadoop.mapred;

import java.io.File;
import java.io.IOException;
import java.lang.management.MemoryType;
import java.lang.management.MemoryUsage;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.Vector;
import java.util.logging.MemoryHandler;
import java.util.Map.Entry;

import org.apache.hadoop.mapred.Reporter;
import java.util.concurrent.ConcurrentHashMap;
import org.apache.hadoop.util.Progress;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.LocalDirAllocator;
import org.apache.hadoop.io.DataInputBuffer;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;

import org.apache.hadoop.util.StringUtils;
import org.apache.hadoop.util.DiskChecker;
import org.apache.hadoop.util.DiskChecker.DiskErrorException;
import org.apache.hadoop.io.WritableUtils;

import org.apache.hadoop.fs.Path;
import org.apache.hadoop.yarn.api.records.ApplicationId;
import org.apache.hadoop.yarn.conf.YarnConfiguration;
import org.apache.hadoop.yarn.server.nodemanager.containermanager.localizer.ContainerLocalizer;
import org.apache.hadoop.yarn.util.ConverterUtils;
import org.apache.hadoop.yarn.util.Records;
import org.apache.hadoop.conf.Configuration;

import java.util.Timer;
import java.util.TimerTask;

import org.apache.hadoop.mapred.JobID;
import org.apache.hadoop.mapred.IndexCacheBridge;
import org.apache.hadoop.mapred.IndexRecordBridge;
import org.apache.hadoop.mapred.JobConf;


class UdaPluginSH extends UdaPlugin {    

	static{
		prepareLog(UdaPluginSH.class.getCanonicalName());
	}

	private Vector<String>     mParams       = new Vector<String>();
	private static LocalDirAllocator localDirAllocator = new LocalDirAllocator ("mapred.local.dir");
	Configuration conf;
	static IndexCacheBridge indexCache;
    private static LocalDirAllocator lDirAlloc =
        new LocalDirAllocator(YarnConfiguration.NM_LOCAL_DIRS);
	private static final Map<String,String> userRsrc = new ConcurrentHashMap<String,String>();
	
	public UdaPluginSH(Configuration conf) {
		super(new JobConf(conf));
		LOG.info("initApp of UdaPluginSH");	
		indexCache = new IndexCacheBridge(mjobConf);
		launchCppSide(false, null); // false: this is TT => we should execute MOFSupplier

	}
	
	public void addJob (String user, JobID jobId){
		userRsrc.put(jobId.toString(), user);
	}
	
	public void removeJob( JobID jobId){
		userRsrc.remove(jobId.toString());
	}
	
	
	protected void buildCmdParams() {
		UdaShuffleProviderPluginShared.buildCmdParams(mCmdParams, mjobConf);
	}

	public void close() {
		UdaShuffleProviderPluginShared.close(LOG);
	}

	//this code is copied from ShuffleHandler.sendMapOutput
	static IndexRecordBridge getPathIndex(String jobIDStr, String mapId, int reduce){
		 String user = userRsrc.get(jobIDStr);

	     IndexRecordBridge data = null;
	        
	     JobID jobID = JobID.forName(jobIDStr);
	     ApplicationId appID = Records.newRecord(ApplicationId.class);
	     appID.setClusterTimestamp(Long.parseLong(jobID.getJtIdentifier()));
	     appID.setId(jobID.getId());
  
	     final String base =
	         ContainerLocalizer.USERCACHE + "/" + user + "/"
	            + ContainerLocalizer.APPCACHE + "/"
	            + ConverterUtils.toString(appID) + "/output" + "/" + mapId;
         if (LOG.isDebugEnabled()) {
           LOG.debug("DEBUG0 " + base);
         }
	     // Index file
	     try{
	        Path indexFileName = lDirAlloc.getLocalPathToRead(
	            base + "/file.out.index", mjobConf);
	        // Map-output file
	        Path mapOutputFileName = lDirAlloc.getLocalPathToRead(
	            base + "/file.out", mjobConf);
	        LOG.debug("DEBUG1 " + base + " : " + mapOutputFileName + " : " +
	            indexFileName);
			 // TODO: is this correct ?? - why user and not runAsUserName like in hadoop-1 ??
		   data = indexCache.getIndexInformationBridge(mapId, reduce, indexFileName, user);
		   data.pathMOF = mapOutputFileName.toString();
	     }catch (IOException e){
	        	LOG.error("got an exception while retrieving the Index Info");}	    
		return data;			
	}
}
