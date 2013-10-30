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
import org.apache.hadoop.mapred.ShuffleConsumerPlugin;
import org.apache.hadoop.mapred.RawKeyValueIterator;
import org.apache.hadoop.mapred.JobConf;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.mapred.Reporter;
import org.apache.hadoop.mapred.MapTaskCompletionEventsUpdate;
import java.io.IOException;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;

import org.apache.hadoop.io.IntWritable;

public class UdaShuffleConsumerPlugin<K, V> implements ShuffleConsumerPlugin, UdaConsumerPluginCallable{

	UdaShuffleConsumerPluginShared  udaPlugin = new UdaShuffleConsumerPluginShared(this);

  @Override // callback from UdaConsumerPluginCallable
	public RawKeyValueIterator pluginCreateKVIterator(ShuffleConsumerPlugin plugin, JobConf job, FileSystem fs, Reporter reporter) throws IOException, InterruptedException {

	  	String type="vanilla";
	    Object iterator;
	    // 1st - try loading the method according to its vanilla signature
	    iterator = Utils.invokeFunctionReflection(ShuffleConsumerPlugin.class, "createKVIterator",
	    		new Class[] {JobConf.class, FileSystem.class, Reporter.class}, plugin, new Object[] {job, fs, reporter});

	    // if failed - this is probably CDH => try loading the method according to its CDH signature
	    if (iterator == null) {
	    	type="cdh";
	    	iterator = Utils.invokeFunctionReflection(ShuffleConsumerPlugin.class, "createKVIterator", new Class[] {}, plugin, new Object[] {});
	    }

    	// still failed => we can't help
    	if (iterator == null) {
    		throw new UdaRuntimeException("can't find createKVIterator not when using its vanilla signature neither when using its CDH signature");
    	}

    	UdaShuffleConsumerPluginShared.LOG.info("loading createKVIterator function with "+type+" signature");

	    return (RawKeyValueIterator)iterator;
	}

  @Override // callback from UdaConsumerPluginCallable
	public Class getVanillaPluginClass(){
		return null;
	}

  @Override // callback from UdaConsumerPluginCallable
	public boolean pluginFetchOutputs(ShuffleConsumerPlugin plugin) throws IOException{
		return plugin.fetchOutputs();
	}

  @Override // callback from UdaConsumerPluginCallable
	public MapTaskCompletionEventsUpdate pluginGetMapCompletionEvents(IntWritable fromEventId, int maxEventsToFetch) throws IOException{
		return udaPlugin.umbilical.getMapCompletionEvents(udaPlugin.reduceTask.getJobID(),
																											fromEventId.get(),
																											maxEventsToFetch,
																											udaPlugin.reduceTask.getTaskID(),
																											udaPlugin.reduceTask.getJvmContext());
	}

  @Override
  public Throwable getMergeThrowable() {
    return null;//mergeThrowable;
  }

  @Override
	public void init(ShuffleConsumerPlugin.Context context) throws IOException {

	    Class noparams[] = {};
	    Object conf;
	    String type="vanilla";

	    // 1st - try loading the method according to its vanilla signature
	    conf = Utils.invokeFunctionReflection(ShuffleConsumerPlugin.Context.class, "getConf", noparams, context, new Object[] {});
	    
	    // if failed - this is probably CDH => try loading the method according to its CDH signature
	    if (conf == null) {
	    	type="cdh";
	    	conf = Utils.invokeFunctionReflection(ShuffleConsumerPlugin.Context.class, "getJobConf", noparams, context, new Object[] {});
	    }

	    // still failed => we can't help
	    if (conf == null) {
	    	throw new UdaRuntimeException("can't find getConf method of vanilla or getJobConf of CDH");
	    }

	    UdaShuffleConsumerPluginShared.LOG.info("loading conf with "+type+" signature");

	    udaPlugin.init(context.getReduceTask(), context.getUmbilical(), (JobConf)conf,  context.getReporter());
	}

  @Override
	public boolean fetchOutputs() throws IOException {
		return udaPlugin.fetchOutputs();
	}

	public RawKeyValueIterator createKVIterator(JobConf job, FileSystem fs, Reporter reporter) throws IOException {
		return udaPlugin.createKVIterator(job, fs, reporter);
	}


	public RawKeyValueIterator createKVIterator() throws IOException {
		FileSystem fs =  FileSystem.getLocal(udaPlugin.jobConf).getRaw(); // Avner: TODO: check
		return udaPlugin.createKVIterator(udaPlugin.jobConf, fs, udaPlugin.reporter);
	}


  @Override
	public void close() {
		udaPlugin.close();
	}

}
