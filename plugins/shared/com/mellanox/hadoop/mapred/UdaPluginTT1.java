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
import org.apache.hadoop.mapred.*;

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

import java.util.Timer;
import java.util.TimerTask;


//*  The following is for MOFSupplier JavaSide. 
class UdaPluginTT extends UdaPlugin {  
	
	static{
		prepareLog(ShuffleProviderPlugin.class.getCanonicalName());
	}

	private static TaskTracker taskTracker;
	private Vector<String>     mParams       = new Vector<String>();
	private static LocalDirAllocator localDirAllocator = new LocalDirAllocator ("mapred.local.dir");
	private static LRUCacheBridgeHadoop1<String, Path> fileCache ;//= new LRUCacheBridgeHadoop1<String, Path>();
	private static LRUCacheBridgeHadoop1<String, Path> fileIndexCache ;//= new LRUCacheBridgeHadoop1<String, Path>();
	static IndexCacheBridge indexCache;
	static UdaShuffleProviderPlugin udaShuffleProvider;

	public UdaPluginTT(TaskTracker taskTracker, JobConf jobConf, UdaShuffleProviderPlugin udaShuffleProvider) {
		super(jobConf);
		this.taskTracker = taskTracker;
		this.udaShuffleProvider = udaShuffleProvider;
		
		launchCppSide(false, null); // false: this is TT => we should execute MOFSupplier
		fileCache = new LRUCacheBridgeHadoop1<String, Path>();
		fileIndexCache = new LRUCacheBridgeHadoop1<String, Path>();

		this.indexCache = new IndexCacheBridge(jobConf);
	}
	
	protected void buildCmdParams() {
		UdaShuffleProviderPluginShared.buildCmdParams(mCmdParams, mjobConf);
	}

	public void close() {
		UdaShuffleProviderPluginShared.close(LOG);
	}
	
	
	//this code is copied from TaskTracker.MapOutputServlet.doGet 
	static IndexRecordBridge getPathIndex(String jobId, String mapId, int reduce){
		 String userName = null;
	     String runAsUserName = null;
	     IndexRecordBridge data = null;
	     
	     try{
	    	 JobConf jobConf = udaShuffleProvider.getJobConfFromSuperClass(JobID.forName(jobId)); 
	    	 userName = jobConf.getUser();
	    	 runAsUserName = taskTracker.getTaskController().getRunAsUser(jobConf);
	    
		    String intermediateOutputDir = UdaShuffleProviderPlugin.getIntermediateOutputDirFromSuperClass(userName, jobId, mapId);
	    
		    String indexKey = intermediateOutputDir + "/file.out.index";
		    Path indexFileName = fileIndexCache.get(indexKey);
		    if (indexFileName == null) {
		        indexFileName = localDirAllocator.getLocalPathToRead(indexKey, mjobConf);
		        fileIndexCache.put(indexKey, indexFileName);
		    }
		      // Map-output file
		    String fileKey = intermediateOutputDir + "/file.out";
		    Path mapOutputFileName = fileCache.get(fileKey);
		    if (mapOutputFileName == null) {
		        mapOutputFileName = localDirAllocator.getLocalPathToRead(fileKey, mjobConf);
		        fileCache.put(fileKey, mapOutputFileName);
		    }
		        
		    //  Read the index file to get the information about where
		    //  the map-output for the given reducer is available. 

		   data = indexCache.getIndexInformationBridge(mapId, reduce, indexFileName, runAsUserName);
		   data.pathMOF = mapOutputFileName.toString();

	    } catch (IOException e) {
			  LOG.error("exception caught" + e.toString()); //to check how C behaves in case there is an exception
		 }
		return data;	
		
	}
	
	
	

}

// Starting to unify code between all our plugins...
class UdaPluginSH {
	static IndexRecordBridge getPathIndex(String jobId, String mapId, int reduce){
		return UdaPluginTT.getPathIndex(jobId, mapId, reduce);
	}
}
