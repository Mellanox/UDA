package com.mellanox.hadoop.mapred;
import org.apache.hadoop.mapred.*;

import java.io.IOException;
import java.net.URI;
import java.net.URL;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;

import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.mapred.JobConf;
//import org.apache.hadoop.mapred.Task.TaskReporter;
import org.apache.hadoop.mapred.TaskAttemptID;
import org.apache.hadoop.util.StringUtils;

public class UdaShuffleConsumerPlugin<K, V> extends ShuffleConsumerPlugin{

	private static final Log LOG = LogFactory.getLog(UdaShuffleConsumerPlugin.class.getName());

	// This is the channel used to transfer the data between RDMA C++ and Hadoop
	private UdaPluginRT rdmaChannel;

	public long getMaxInMemReduce() {
		return maxInMemReduce;
	}
		
	protected void initPlugin() throws ClassNotFoundException, IOException {
		this.rdmaChannel = new UdaPluginRT<K,V>(this, reduceTask, jobConf, reporter, reduceTask.getNumMaps());
	}
	
	protected boolean fetchOutputs() {
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


	/**
	 * 
	 * TaskTracker notified us that a reset is required
	 * This may be needed for syncing with jobtracker for job that was recovered
	 * 
	 */
	public void resetKnownMaps() {
		// not supported yet in UDA (assuming sunny day scenario)
	}


	// Process the TaskCompletionEvent:
	// 1. Save the SUCCEEDED maps in knownOutputs to fetch the outputs.
	// 2. Save the OBSOLETE/FAILED/KILLED maps in obsoleteOutputs to stop 
	//    fetching from those maps.
	// 3. Remove TIPFAILED maps from neededOutputs since we don't need their
	//    outputs at all.
	public void mapCompleted(TaskCompletionEvent event) throws IOException {
		switch (event.getTaskStatus()) {
		case SUCCEEDED:
		{
			URI u = URI.create(event.getTaskTrackerHttp());
			String host = u.getHost();
			TaskAttemptID taskId = event.getTaskAttemptId();
			URL mapOutputUrl = new URL(event.getTaskTrackerHttp() + 
					"/mapOutput?job=" + taskId.getJobID() +
					"&map=" + taskId + 
					"&reduce=" + reduceTask.getPartition());

			MapOutputLocation mapOutputLocation = new MapOutputLocation(taskId, host, mapOutputUrl); 
			rdmaChannel.sendFetchReq(host, mapOutputLocation.getTaskAttemptId().getJobID().toString()  , mapOutputLocation.getTaskAttemptId().toString());  			
		}
		break;
		case FAILED:
		case KILLED:
		case OBSOLETE:
		{
			//obsoleteMapIds.add(event.getTaskAttemptId());
			LOG.info("Ignoring obsolete output of " + event.getTaskStatus() + 
					" map-task: '" + event.getTaskAttemptId() + "'");
			LOG.warn("UNSUPPORTED EVENT");
		}
		break;
		case TIPFAILED:
		{
			//copiedMapOutputs.add(event.getTaskAttemptId().getTaskID());
			LOG.info("Ignoring output of failed map TIP: '" +  
					event.getTaskAttemptId() + "'");
			LOG.warn("UNSUPPORTED EVENT");
		}
		break;
		}

	}

	
	/**
	 * For rdma setting
	 */
	public RawKeyValueIterator createKVIterator(
			JobConf job, FileSystem fs, Reporter reporter) throws IOException {

			return this.rdmaChannel.createKVIterator_rdma(job,fs,reporter);
	}

	public void close() {
			this.rdmaChannel.close();
	}
	
}
