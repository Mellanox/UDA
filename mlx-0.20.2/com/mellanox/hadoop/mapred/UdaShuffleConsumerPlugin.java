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

//import org.apache.hadoop.mapred.ReduceTask.ReduceCopier.MapOutputLocation;
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
	
	private static final Log LOG = LogFactory.getLog(UdaShuffleConsumerPlugin.class.getName());
	
	// This is the channel used to transfer the data between RDMA C++ and Hadoop
	private UdaPluginRT rdmaChannel;
	
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
	protected void init(ReduceTask reduceTask, TaskUmbilicalProtocol umbilical, JobConf conf, Reporter reporter) throws IOException {

		this.reduceTask = reduceTask;
		this.reduceId = reduceTask.getTaskID();
		
		this.umbilical = umbilical;
		this.jobConf = conf;
		this.reporter = reporter;

		configureClasspath(jobConf);
		this.rdmaChannel = new UdaPluginRT<K,V>(this, reduceTask, jobConf, reporter, reduceTask.getNumMaps());
	}
	
    
	
	/*
		public long getMaxInMemReduce() {
		return maxInMemReduce;
		}
	//*/		
	
	/** 
		* A flag to indicate when to exit getMapEvents thread 
	*/
	protected volatile boolean exitGetMapEvents = false; //TODO: no need volatile
	
	public boolean fetchOutputs() {
		GetMapEventsThread getMapEventsThread = null;
		// start the map events thread
		getMapEventsThread = new GetMapEventsThread();
		getMapEventsThread.start();         
		
		LOG.info("UdaShuffleConsumerPlugin: Wait for fetching");
		synchronized(this) {
			try {
				this.wait(); 
				} catch (InterruptedException e) {
			}       
		}
		LOG.info("UdaShuffleConsumerPlugin: Fetching is done"); 
		// all done, inform the copiers to exit
		exitGetMapEvents= true;
		try {
			//here only stop the thread, but don't close it, 
			//because we need this channel to return the values later.
			getMapEventsThread.join();
			LOG.info("getMapsEventsThread joined.");
			} catch (InterruptedException ie) {
			LOG.info("getMapsEventsThread/rdmaChannelThread threw an exception: " +
			StringUtils.stringifyException(ie));
		}
		return true;
	}   
	
	public RawKeyValueIterator createKVIterator(JobConf job, FileSystem fs, Reporter reporter) throws IOException {
		return this.rdmaChannel.createKVIterator_rdma(job,fs,reporter);
	}
	
	public void close() {
		this.rdmaChannel.close();
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
				}
				catch (Throwable t) {
					String msg = reduceTask.getTaskID()
					+ " GetMapEventsThread Ignoring exception : " 
					+ StringUtils.stringifyException(t);
					pluginReportFatalError(reduceTask, reduceTask.getTaskID(), t, msg);
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
			
			// Check if the reset is required.
			// Since there is no ordering of the task completion events at the 
			// reducer, the only option to sync with the new jobtracker is to reset 
			// the events index
			if (update.shouldReset()) {
				fromEventId.set(0);
				//          obsoleteMapIds.clear(); // clear the obsolete map
				//          mapLocations.clear(); // clear the map locations mapping
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
						TaskAttemptID taskId = event.getTaskAttemptId();
						rdmaChannel.sendFetchReq(host, taskId.getJobID().toString()  , taskId.toString());  // Avner: notify RDMA
						numNewMaps ++;
					}
					break;
					case FAILED:
					case KILLED:
					case OBSOLETE:
					{
						//              obsoleteMapIds.add(event.getTaskAttemptId());
						LOG.info("Ignoring obsolete output of " + event.getTaskStatus() + 
						" map-task: '" + event.getTaskAttemptId() + "'");
					}
					break;
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
