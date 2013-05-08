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

import org.apache.hadoop.mapred.JobConf;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.mapred.Reporter;
import org.apache.hadoop.mapred.ShuffleConsumerPlugin;
import org.apache.hadoop.mapred.RawKeyValueIterator;
import org.apache.hadoop.mapred.TaskID;
import org.apache.hadoop.mapred.Task;
import org.apache.hadoop.mapred.MapTaskCompletionEventsUpdate;
import org.apache.hadoop.mapred.TaskCompletionEvent;
import org.apache.hadoop.mapred.TaskAttemptID;
import org.apache.hadoop.mapred.TaskUmbilicalProtocol;
import org.apache.hadoop.mapred.ReduceTask;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;

import org.apache.hadoop.fs.Path;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.mapred.JobConf;
import org.apache.hadoop.util.StringUtils;
import org.apache.hadoop.io.IntWritable;

import java.io.File;
import java.io.IOException;
import java.net.URI;
import java.net.URL;
import java.net.URLClassLoader;

import java.util.ArrayList;
import java.util.List;
import java.util.LinkedList;
import java.util.Collections;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;  // TODO: probably concurrency is not needed 

import java.util.Set;
import java.util.TreeSet;


import org.apache.hadoop.mapred.UdaMapredBridge;
import org.apache.hadoop.fs.FSError;

/**
	* Abstraction to track a map-output.
*/
class MapOutputLocation {
	TaskAttemptID taskAttemptId;
	TaskID taskId;
	String ttHost;
	URL taskOutput;
	
	public MapOutputLocation(TaskAttemptID taskAttemptId, 
	String ttHost, URL taskOutput) {
        this.taskAttemptId = taskAttemptId;
        this.taskId = this.taskAttemptId.getTaskID();
        this.ttHost = ttHost;
        this.taskOutput = taskOutput;
	}
	
	public TaskAttemptID getTaskAttemptId() {
        return taskAttemptId;
	}
	
	public TaskID getTaskId() {
        return taskId;
	}
	
	public String getHost() {
        return ttHost;
	}
	
	public URL getOutputLocation() {
        return taskOutput;
	}
}



public class UdaShuffleConsumerPlugin<K, V> extends ShuffleConsumerPlugin{
	
	protected ReduceTask reduceTask;
	protected TaskAttemptID reduceId;
	protected TaskUmbilicalProtocol umbilical; // Reference to the umbilical object
	protected JobConf jobConf;
	protected Reporter reporter;
	
	private static final Log LOG = LogFactory.getLog(ShuffleConsumerPlugin.class.getCanonicalName());
	
	// This is the channel used to transfer the data between RDMA C++ and Hadoop
	private UdaPluginRT rdmaChannel;
	
	ShuffleConsumerPlugin fallbackPlugin = null;
	

	// let other thread wake up fetchOutputs upon completion (either success of failure)
	private Object fetchLock = new Object();
	void notifyFetchCompleted(){
		synchronized(fetchLock) {
			fetchLock.notify();
		}		
	}
	
	// called outside the RT thread, usually by a UDA C++ thread
	void failureInUda(Throwable t) {

		if (LOG.isDebugEnabled()) LOG.debug("failureInUda");
		
		try {
			doFallbackInit(t);
			
			// wake up fetchOutputs
			synchronized(fetchLock) { 
				fetchLock.notify();
			}
		}
		catch(Throwable t2){
			throw new UdaRuntimeException("Failure in UDA and failure when trying to fallback to vanilla", t2);
		}
	}
	
	synchronized private void doFallbackInit(Throwable t) throws IOException {
		if (fallbackPlugin != null)
			return;  // already done
		
		if (t != null) {
			LOG.error("Critical failure has occured in UdaPlugin - We'll try to use vanilla as fallbackPlugin. \n\tException is:" + StringUtils.stringifyException(t));
		}

		try {
			fallbackPlugin = UdaMapredBridge.getShuffleConsumerPlugin(null, reduceTask, umbilical, jobConf, reporter);
			LOG.info("Succesfuly switched to Using fallbackPlugin");
		}
		catch (ClassNotFoundException e) {
			UdaRuntimeException ure = new UdaRuntimeException("Failed to initialize UDA Shuffle and failed to fallback to vanilla Shuffle because of ClassNotFoundException", e);
			ure.setStackTrace(e.getStackTrace());
			throw ure;
		}		
	}
	
	boolean fallbackFetchOutputsDone = false;
	synchronized private boolean doFallbackFetchOutputs() throws IOException {
		if (fallbackFetchOutputsDone) 
			return true;  // already done
		
		doFallbackInit(null); // sanity
		fallbackFetchOutputsDone = fallbackPlugin.fetchOutputs();
		return fallbackFetchOutputsDone;
	}
	
	
	
	/**
		* initialize this ShuffleConsumer instance.  The base class implementation will initialize its members and 
		* then invoke init for plugin specific initiaiztion
		* 
		* @param reduceTask
		* @param umbilical
		* @param jobConf
		* @param reporter
		* @throws ClassNotFoundException
		* @throws IOException
	*/
    @Override
	public void init(ReduceTask reduceTask, TaskUmbilicalProtocol umbilical, JobConf conf, Reporter reporter) throws IOException {

		try {
			LOG.info("init - Using UdaShuffleConsumerPlugin");
			this.reduceTask = reduceTask;
			this.reduceId = reduceTask.getTaskID();
			
			this.umbilical = umbilical;
			this.jobConf = conf;
			this.reporter = reporter;
	
			configureClasspath(jobConf);
			this.rdmaChannel = new UdaPluginRT<K,V>(this, reduceTask, jobConf, reporter, reduceTask.getNumMaps());
		}
		catch (Throwable t) {
			doFallbackInit(t);
		}
	}
	
    
	
	/** 
		* A flag to indicate when to exit getMapEvents thread 
	*/
	protected volatile boolean exitGetMapEvents = false;

	boolean fetchOutputsCompleted = false;
	private boolean fetchOutputsInternal() throws IOException {
		GetMapEventsThread getMapEventsThread = null;
		// start the map events thread
		getMapEventsThread = new GetMapEventsThread();
		getMapEventsThread.start();         
		
		LOG.info("fetchOutputs - Using UdaShuffleConsumerPlugin");
		synchronized(fetchLock) {
			try {
				fetchLock.wait(); 
				} catch (InterruptedException e) {
			}       
		}
		// all done, inform the copiers to exit
		exitGetMapEvents= true;
		if (LOG.isDebugEnabled()) LOG.debug("Fetching finished"); 

		if (fallbackPlugin != null) {
			LOG.warn("another thread has indicated Uda failure");
			throw new UdaRuntimeException("another thread has indicated Uda failure");
		}
		try {
			//here only stop the thread, but don't close it, 
			//because we need this channel to return the values later.
			getMapEventsThread.join();
			LOG.info("getMapsEventsThread joined.");
		} catch (InterruptedException ie) {
			LOG.info("getMapsEventsThread/rdmaChannelThread threw an exception: " +
					StringUtils.stringifyException(ie));
		}
		fetchOutputsCompleted = true;
		return true;
	}
	
    @Override
	public boolean fetchOutputs() throws IOException {
		
		try {
			if (fallbackPlugin == null) {
				return fetchOutputsInternal();
			}
		}
		catch (Throwable t) {		
			doFallbackInit(t);
		}

		LOG.info("fetchOutputs: Using fallbackPlugin");
		return doFallbackFetchOutputs();		
	}   
	
    //playback of fetchOutputs from other thread - will handle error return to exception like RT does
	private void doPlaybackFetchOutputs() throws IOException {
		
		LOG.info("doPlaybackFetchOutputs: Using fallbackPlugin");

		// error handling code copied from ReduceTask.java
		if (!doFallbackFetchOutputs()) {
			
/* - commented out till mergeThrowable is accessible - requires change in the patch								
			if(fallbackPlugin.mergeThrowable instanceof FSError) {
				throw (FSError)fallbackPlugin.mergeThrowable;
			}
			throw new IOException("Task: " + reduceTask.getTaskID() + 
					" - The reduce copier failed", fallbackPlugin.mergeThrowable);
//*/
			throw new IOException("Task: " + reduceTask.getTaskID() + 
					" - The reduce copier failed");
			}
	}   
	
    @Override
	public RawKeyValueIterator createKVIterator(JobConf job, FileSystem fs, Reporter reporter) throws IOException {
		
		try {
			if (fetchOutputsCompleted) {
				LOG.info("createKVIterator - Using UdaShuffleConsumerPlugin");
				return this.rdmaChannel.createKVIterator_rdma(job,fs,reporter);
			}
		}
		catch (Throwable t) {		
			doFallbackInit(t);
		}

		if (! fallbackFetchOutputsDone) 
			doPlaybackFetchOutputs();//this will also playback init - if needed

		LOG.info("createKVIterator: Using fallbackPlugin");
		return fallbackPlugin.createKVIterator(job, fs, reporter);
	}

    private class UdaCloserThread extends Thread {
    	UdaPluginRT rdmaChannel;
		public UdaCloserThread(UdaPluginRT rdmaChannel) {
			this.rdmaChannel = rdmaChannel;
			setName("UdaCloserThread");
			setDaemon(true);
		}
		
		@Override
		public void run() {
			LOG.info(reduceTask.getTaskID() + " Thread started: " + getName());
			if (rdmaChannel == null) {
				LOG.warn("rdmaChannel == null");				
			}
			else {
				LOG.info("--->>> closing UdaShuffleConsumerPlugin");
				rdmaChannel.close();				
				LOG.info("<<<--- UdaShuffleConsumerPlugin was closed");
			}
			LOG.info(reduceTask.getTaskID() + " Thread finished: " + getName());
		}
    }
    
    @Override
	public void close() {
		// try catch here is not needed since it is too late for new fallback to vanilla.
		if (fallbackPlugin == null) {
			LOG.info("close - Using UdaShuffleConsumerPlugin");
			this.rdmaChannel.close();
			LOG.info("====XXX Successfully closed UdaShuffleConsumerPlugin XXX====");

			return;
		}

		LOG.info("close: Using fallbackPlugin");
		fallbackPlugin.close();
	
		// also close UdaPlugin including C++
		UdaCloserThread udaCloserThread = new UdaCloserThread(rdmaChannel);
		udaCloserThread.start();
		try {
			udaCloserThread.join(1000);  // wait up to 1 second for the udaCloserThread
		}
		catch (InterruptedException e){LOG.info("InterruptedException on udaCloserThread.join");}
		LOG.info("====XXX Successfully closed fallbackPlugin XXX====");
	}
	
	
	
	
	//*	
	protected void configureClasspath(JobConf conf)
	throws IOException {
		
		// get the task and the current classloader which will become the parent
		Task task = reduceTask;
		ClassLoader parent = conf.getClassLoader();   
		
		// get the work directory which holds the elements we are dynamically
		// adding to the classpath
		File workDir = new File(task.getJobFile()).getParentFile();
		ArrayList<URL> urllist = new ArrayList<URL>();
		
		// add the jars and directories to the classpath
		String jar = conf.getJar();
		if (jar != null) {      
			File jobCacheDir = new File(new Path(jar).getParent().toString());
			
			File[] libs = new File(jobCacheDir, "lib").listFiles();
			if (libs != null) {
				for (int i = 0; i < libs.length; i++) {
					urllist.add(libs[i].toURL());
				}
			}
			urllist.add(new File(jobCacheDir, "classes").toURL());
			urllist.add(jobCacheDir.toURL());
			
		}
		urllist.add(workDir.toURL());
		
		// create a new classloader with the old classloader as its parent
		// then set that classloader as the one used by the current jobconf
		URL[] urls = urllist.toArray(new URL[urllist.size()]);
		URLClassLoader loader = new URLClassLoader(urls, parent);
		conf.setClassLoader(loader);
	}
	//*/
	
    private class GetMapEventsThread extends Thread {
		
		private IntWritable fromEventId = new IntWritable(0);
		private static final long SLEEP_TIME = 1000;
		
		
		
		
		public GetMapEventsThread() {
			setName("Thread for polling Map Completion Events");
			setDaemon(true);
		}
		
		@Override
		public void run() {
			
			LOG.info(reduceTask.getTaskID() + " Thread started: " + getName());
			
			do {
				try {
					int numNewMaps = getMapCompletionEvents();
					if (numNewMaps > 0) {
						//              synchronized (copyResultsOrNewEventsLock) {
						//                numEventsFetched += numNewMaps;
						//                copyResultsOrNewEventsLock.notifyAll();
						//              }
					}
					if (LOG.isDebugEnabled()) {
						if (numNewMaps > 0) {
							LOG.debug(reduceTask.getTaskID() + ": " +  
							"Got " + numNewMaps + " new map-outputs"); 
						}
					}
					Thread.sleep(SLEEP_TIME);
				} 
				catch (InterruptedException e) {
					LOG.warn(reduceTask.getTaskID() +
					" GetMapEventsThread returning after an " +
					" interrupted exception");
					return;
					//TODO: do we want fallback to vanilla??
				}
				catch (Throwable t) {
/*					
					String msg = reduceTask.getTaskID()
					+ " GetMapEventsThread Ignoring exception : " 
					+ StringUtils.stringifyException(t);
					pluginReportFatalError(reduceTask, reduceTask.getTaskID(), t, msg);
//*/					
					LOG.error("error in GetMapEventsThread");
					failureInUda(t);
					break;
				}
			} while (!exitGetMapEvents);
			
			LOG.info("GetMapEventsThread exiting");
			
		}
		
		/** Max events to fetch in one go from the tasktracker */
		private static final int MAX_EVENTS_TO_FETCH = 10000;
		
		/**
			* The map for (Hosts, List of MapIds from this Host) maintaining
			* map output locations
		*/
		private final Map<String, List<MapOutputLocation>> mapLocations = 
		new ConcurrentHashMap<String, List<MapOutputLocation>>();
		
		/** 
			* Queries the {@link TaskTracker} for a set of map-completion events 
			* from a given event ID.
			* @throws IOException
		*/  
		private int getMapCompletionEvents() throws IOException {
			
			int numNewMaps = 0;
			
			MapTaskCompletionEventsUpdate update = 
			umbilical.getMapCompletionEvents(reduceTask.getJobID(), 
			fromEventId.get(), 
			MAX_EVENTS_TO_FETCH,
			reduceTask.getTaskID(), reduceTask.getJvmContext());
			TaskCompletionEvent events[] = update.getMapTaskCompletionEvents();

			Set <TaskID>        succeededTasks    = new TreeSet<TaskID>();
			Set <TaskAttemptID> succeededAttempts = new TreeSet<TaskAttemptID>();

			// Check if the reset is required.
			// Since there is no ordering of the task completion events at the 
			// reducer, the only option to sync with the new jobtracker is to reset 
			// the events index
			if (update.shouldReset()) {
				fromEventId.set(0);
				//          obsoleteMapIds.clear(); // clear the obsolete map
				//          mapLocations.clear(); // clear the map locations mapping
				
				if (succeededTasks.isEmpty()) {
					//ignore
					LOG.info("got reset update before we had any succeeded map - this is OK");
				}
				else {
					//fallback			
					throw new UdaRuntimeException("got reset update, after " + succeededTasks.size() + " succeeded maps" );
				}
			}
			
			// Update the last seen event ID
			fromEventId.set(fromEventId.get() + events.length);
			
			// Process the TaskCompletionEvents:
			// 1. Save the SUCCEEDED maps in knownOutputs to fetch the outputs.
			// 2. Save the OBSOLETE/FAILED/KILLED maps in obsoleteOutputs to stop 
			//    fetching from those maps.
			// 3. Remove TIPFAILED maps from neededOutputs since we don't need their
			//    outputs at all.
			for (TaskCompletionEvent event : events) {
				switch (event.getTaskStatus()) {
					case SUCCEEDED:
					{
						URI u = URI.create(event.getTaskTrackerHttp());
						String host = u.getHost();
						TaskAttemptID taskAttemptId = event.getTaskAttemptId();
						succeededAttempts.add(taskAttemptId); // add to collection

						TaskID coreTaskId = taskAttemptId.getTaskID();
						if (succeededTasks.contains(coreTaskId)) {
							//ignore
							LOG.info("Ignoring succeeded attempt, since we already got success event" +
									" for this task, new attempt is: '" +  taskAttemptId + "'");
						}
						else {
							succeededTasks.add(coreTaskId); // add to collection
							rdmaChannel.sendFetchReq(host, taskAttemptId.getJobID().toString()  , taskAttemptId.toString());
							numNewMaps ++;
						}
					}
					break;
					case FAILED:
					case KILLED:
					case OBSOLETE:
					{

						TaskAttemptID taskAttemptId = event.getTaskAttemptId();
						if (succeededAttempts.contains(taskAttemptId)) {
							//fallback
							
							String errorMsg = "encountered obsolete map attempt" +
								" after this attempt was already successful. TaskStatus=" + event.getTaskStatus() +
								" new attempt: '" + taskAttemptId + "'";

							throw new UdaRuntimeException(errorMsg);
						}
						else {
							//ignore
							LOG.info("Ignoring failed attempt: '" +  taskAttemptId + "' with TaskStatus=" + event.getTaskStatus() + 
									" that was not reported to C++ before");
						}

					}
					// break; - break is unreachable after throw
					case TIPFAILED:
					{
						//              copiedMapOutputs.add(event.getTaskAttemptId().getTaskID());
						LOG.info("Ignoring output of failed map TIP: '" +  
						event.getTaskAttemptId() + "'");
					}
					break;
				}
			}
			return numNewMaps;
		}
	}
}
