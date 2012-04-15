package com.mellanox.hadoop.mapred;
//import KillJobAction;
//import TaskTracker;

import org.apache.hadoop.mapred.*;

import java.io.IOException;
import java.net.URI;
import java.net.URL;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;

import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.mapred.JobConf;
import org.apache.hadoop.mapred.TaskAttemptID;
import org.apache.hadoop.mapreduce.security.token.JobTokenSecretManager;
import org.apache.hadoop.util.StringUtils;

public class UdaShuffleProviderPlugin extends ShuffleProviderPlugin{

	private static final Log LOG = LogFactory.getLog(UdaShuffleProviderPlugin.class.getName());

	// This is the channel used to transfer the data between RDMA C++ and Hadoop
	private UdaPluginTT rdmaChannel;

	
	/**
	 * Do the real constructor work here.  It's in a separate method
	 * so we can call it again and "recycle" the object after calling
	 * close().
	 * 
	 * invoked at the end of TaskTracker.initialize
	 */
	public void initialize(TaskTracker taskTracker) {
		super.initialize(taskTracker);
		rdmaChannel = new UdaPluginTT(taskTracker, getJobConf());
	}

	/**
	 * close and cleanup any resource, including threads and disk space.  
	 * A new object within the same process space might be restarted, 
	 * so everything must be clean.
	 * 
	 * invoked at the end of TaskTracker.close
	 */
	public void close() {
		rdmaChannel.close();
	}


	/**
	 * notification for start of a new job
	 *  
	 * @param rjob
	 */
	public void jobInit(TaskTracker.RunningJob rjob) {
		// nothing to do!		
	}
					  
	
	  /**
	   * a map task is done.
	   * 
	   * invoked at the end of TaskTracker.done, under: if (task.isMapTask())
	   */ 
	public void mapDone(String userName, String jobId, String taskId, Path fileOut, Path fileOutIndex) {
		rdmaChannel.notifyMapDone(userName, jobId, taskId, fileOut, fileOutIndex);
	}
	
	  /**
	   * The task tracker is done with this job, so we need to clean up.
	   * 
	   * invoked at the end of TaskTracker.jobDone
	   * @param action The action with the job
	   */
	public void jobDone(KillJobAction action) {
		rdmaChannel.jobOver(action.getJobID().toString());
	}
	
}
