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

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
import java.net.URLClassLoader;
import java.util.ArrayList;

import org.apache.hadoop.mapred.JobConf;
import org.apache.hadoop.mapred.Task;
import org.apache.hadoop.mapred.Task.TaskReporter;
import org.apache.hadoop.mapred.TaskTracker;
import org.apache.hadoop.mapred.ReduceTask.ReduceCopier;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.IntWritable;
import org.apache.hadoop.util.ReflectionUtils;
import org.apache.hadoop.util.StringUtils;


/**
 * Plugin to serve Reducers who request MapOutput from TaskTrackers that use a matching ShuffleProvidePlugin
 * 
 */
public abstract class ShuffleConsumerPlugin {

	/**
	 * Factory method for getting the ShuffleConsumerPlugin from the given class object and configure it. 
	 * If clazz is null, this method will return instance of ReduceCopier since it is the default ShuffleConsumerPlugin 
	 * 
	 * @param clazz
	 * @param reduceTask
	 * @param umbilical
	 * @param conf configure the plugin with this
	 * @param reporter
	 * @return
	 * @throws ClassNotFoundException
	 * @throws IOException
	 */
	public static ShuffleConsumerPlugin getShuffleConsumerPlugin(Class<? extends ShuffleConsumerPlugin> clazz, ReduceTask reduceTask, 
			TaskUmbilicalProtocol umbilical, JobConf conf, TaskReporter reporter) throws ClassNotFoundException, IOException  {

		if (clazz != null && ((Class)clazz) != ReduceTask.ReduceCopier.class) {
			ShuffleConsumerPlugin plugin = ReflectionUtils.newInstance(clazz, conf);
			plugin.init(reduceTask, umbilical, conf, reporter);
			return plugin;
		}

		return reduceTask.new ReduceCopier(umbilical, conf, reporter); // default plugin is an inner class of ReduceTask
	}
	
	/**
	 * initialize this instance after it was created by factory using empty CTOR. @see getShuffleConsumerPlugin
	 * 
	 * @param reduceTask
	 * @param umbilical
	 * @param conf
	 * @param reporter
	 * @throws IOException
	 */
	protected void init(ReduceTask reduceTask, TaskUmbilicalProtocol umbilical, JobConf conf, Reporter reporter) throws IOException{
	}

	/**
	 * close and clean any resource associated with this object
	 */
	public void close(){
	}

	/**
	 * fetch output of mappers from TaskTrackers
	 * @return true iff success.  In case of failure an appropriate value may be set in mergeThrowable member
	 * @throws IOException - this 'throws' is only for backward compatibility withReduceCopier.fetchOutputs() signature.
	 * we don't really need it, since we use mergeThrowable member
	 */
	abstract public boolean fetchOutputs() throws IOException;

	/**
	 * Create a RawKeyValueIterator from copied map outputs. 
	 * 
	 * The iterator returned must satisfy the following constraints:
	 *   1. Fewer than io.sort.factor files may be sources
	 *   2. No more than maxInMemReduce bytes of map outputs may be resident
	 *      in memory when the reduce begins
	 *
	 * If we must perform an intermediate merge to satisfy (1), then we can
	 * keep the excluded outputs from (2) in memory and include them in the
	 * first merge pass. If not, then said outputs must be written to disk
	 * first.
	 */
	abstract public RawKeyValueIterator createKVIterator(JobConf job, FileSystem fs, Reporter reporter) throws IOException;



	/**
	 * A reference to the throwable object (if merge throws an exception)
	 */
	protected volatile Throwable mergeThrowable;

	/**
	 * a utility function that wraps Task.reportFatalError for serving sub classes that are not part of this package
	 *    
	 * @param reduceTask
	 * @param id
	 * @param throwable
	 * @param logMsg
	 */
	protected void pluginReportFatalError(ReduceTask reduceTask, TaskAttemptID id, Throwable throwable, String logMsg) {	   
		reduceTask.reportFatalError(id, throwable, logMsg);
	}

}
