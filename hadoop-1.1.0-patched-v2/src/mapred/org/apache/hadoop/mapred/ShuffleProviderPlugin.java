/**
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.apache.hadoop.mapred;

import java.util.Map;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.fs.LocalDirAllocator;
import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.util.ReflectionUtils;
import org.apache.hadoop.mapred.TaskTracker.RunningJob;

/**
 * This interface is implemented by objects that are able to answer shuffle requests which are
 * sent from a matching Shuffle Consumer that lives in context of a ReduceTask object.
 * 
 * ShuffleProvider object will be notified on the following events: 
 * initialize, close, taskDone, jobDone.
 * At this phase, at most one optional ShuffleProvider is supported 
 * At this phase, the optional ShuffleProvider (if any) will work in addition to Hadoop's default 
 * shuffle provider (Jetty/Netty)
 *
 */
public abstract class ShuffleProviderPlugin {


	/**
	 * Factory method for getting the ShuffleProviderPlugin from the given class object and configure it. 
	 * If clazz is null, this method will return null
	 * 
	 * @param clazz class
	 * @param conf configure the plugin with this.
	 * @return ShuffleProviderPlugin
	 */
	public static ShuffleProviderPlugin getShuffleProviderPlugin(Class<? extends ShuffleProviderPlugin> clazz, Configuration conf) {
		if (clazz != null) {
			return ReflectionUtils.newInstance(clazz, conf);
		}
		else {
			return null; // no extra ShuffleProvider
		}

	}

	protected TaskTracker taskTracker; //handle to parent object

	/**
	 * Do the real constructor work here.  It's in a separate method
	 * so we can call it again and "recycle" the object after calling
	 * close().
	 * 
	 * invoked at the end of TaskTracker.initialize
	 */
	public void initialize(TaskTracker taskTracker) {
		this.taskTracker = taskTracker;
	}

	/**
	 * close and cleanup any resource, including threads and disk space.  
	 * A new object within the same process space might be restarted, 
	 * so everything must be clean.
	 * 
	 * invoked at the end of TaskTracker.close
	 */
	public abstract void close();

	/**
	 * a task is done.
	 * invoked at the end of TaskTracker.done, sub class can check: if (task.isMapTask())
	 * and use localDirAllocator for finding MOF(s) locations 
	 * 
	 */ 
	public abstract void taskDone(Task task, LocalDirAllocator localDirAllocator);

	/**
	 * The task tracker is done with this job, so we need to clean up.
	 * invoked at the end of TaskTracker.jobDone
	 * 
	 * @param jobID
	 */
	public abstract void jobDone(JobID jobID);

	//
	// Utility functions for serving sub-classes that are not part of mapred package
	//
	
	protected JobConf getJobConf() {
		return taskTracker.getJobConf();
	}
	
	protected JobConf getJobConf(JobID jobid) {
		return taskTracker.runningJobs.get(jobid).getJobConf();
	}
	
	protected static String getIntermediateOutputDir(String user, String jobid, String taskid) {
		return TaskTracker.getIntermediateOutputDir(user, jobid, taskid);
	}
}
