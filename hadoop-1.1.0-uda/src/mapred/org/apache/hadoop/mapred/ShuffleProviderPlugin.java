
package org.apache.hadoop.mapred;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.mapreduce.security.token.JobTokenSecretManager;
import org.apache.hadoop.util.ReflectionUtils;
import org.apache.hadoop.fs.Path;

/**
 * This interface is implemented by objects that are able to serve as Shuffle Providers
 * and satisfy shuffle requests originated by a matching Shuffle Consumer 
 * that lives in a context of a ReduceTask object 
 * 
 * All ShuffleProvider objects will be notified on the following events: 
 * initialize, close, mapDone, jobDone.
 * In addition, Hadoop's default provider (either Jetty or Netty) will always 
 * be notified (and there is no need to mention it in configuration files). 
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
	 * notification for start of a new job
	 *  
	 * @param rjob
	 */
	public abstract void jobInit(TaskTracker.RunningJob rjob);
					  
	
	  /**
	   * a map task is done.
	   * 
	   * invoked at the end of TaskTracker.done, under: if (task.isMapTask())
	   * 
	   * Todo: consider class with all these fields as one argument
	   */ 
	public abstract void mapDone(String userName, String jobId, String taskId, Path fileOut, Path fileOutIndex);
	
	  /**
	   * The task tracker is done with this job, so we need to clean up.
	   * 
	   * invoked at the end of TaskTracker.jobDone
	   * @param action The action with the job
	   */
	public abstract void jobDone(KillJobAction action);

	protected JobConf getJobConf() {
		return taskTracker.getJobConf();
	}
	/**
	 * 
	 * @return JobTokenSecretManager from tasktracker
	 */
	protected JobTokenSecretManager getJobTokenSecretManager() {
		return taskTracker.getJobTokenSecretManager();
	}

}
