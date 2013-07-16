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

import java.io.IOException;
import org.apache.hadoop.util.ReflectionUtils;
import org.apache.hadoop.fs.FileSystem;

import org.apache.hadoop.mapred.Reducer;
import org.apache.hadoop.fs.LocalDirAllocator;
import org.apache.hadoop.io.compress.CompressionCodec;
import org.apache.hadoop.util.Progress;

import org.apache.hadoop.mapred.Counters;
import org.apache.hadoop.mapred.TaskStatus;

import org.apache.hadoop.fs.FSError;

import java.util.Set;
import java.util.TreeSet;

import org.apache.hadoop.mapred.UdaMapredBridge;



public class UdaShuffleConsumerPlugin<K, V> implements ShuffleConsumerPlugin<K, V>, UdaConsumerPluginCallable{

	UdaShuffleConsumerPluginShared  udaPlugin = new UdaShuffleConsumerPluginShared(this);

  @Override // callback from UdaConsumerPluginCallable
	public boolean pluginFetchOutputs(ShuffleConsumerPlugin plugin) throws IOException{
		return true; //TODO: avner - clarify this is for vanilla !!
	}

  @Override // callback from UdaConsumerPluginCallable
	public RawKeyValueIterator pluginCreateKVIterator(ShuffleConsumerPlugin plugin, JobConf job, FileSystem fs, Reporter reporter)
																										throws IOException, InterruptedException{
		return plugin.run(); //TODO: avner - clarify this is for vanilla !!
	}

  @Override // callback from UdaConsumerPluginCallable
	public Class getVanillaPluginClass(){
		return null;
	}

  @Override // callback from UdaConsumerPluginCallable
	public MapTaskCompletionEventsUpdate pluginGetMapCompletionEvents(IntWritable fromEventId, int maxEventsToFetch) throws IOException{
		return udaPlugin.umbilical.getMapCompletionEvents(udaPlugin.reduceTask.getJobID(), 
																											fromEventId.get(), 
																											maxEventsToFetch,
																											udaPlugin.reduceTask.getTaskID()
																											//, udaPlugin.reduceTask.getJvmContext() - this was for hadoop-1.x
																											);
	}
	
  static public ShuffleConsumerPlugin.Context staticContext; // TODO: avner - try to avoid static
  public void init(ShuffleConsumerPlugin.Context<K, V> context) {
  staticContext = context;
		try {
			udaPlugin.init((ReduceTask)context.getReduceTask(), context.getUmbilical(), context.getJobConf(), context.getReporter(), context.getLocalFS());
			// DoNOT call in hadoop-3, udaPlugin.configureClasspath(this.jobConf);
		}
		catch (Exception e) {
			udaPlugin.LOG.error("error occured at plugin init");
		}
	}

	public RawKeyValueIterator run() throws IOException, InterruptedException{
		if (udaPlugin.fetchOutputs()) {
			return udaPlugin.createKVIterator(udaPlugin.jobConf, udaPlugin.fs, udaPlugin.reporter);
		}
		else {
			throw new IOException("critical failure in udaPlugin.fetchOutputs()");
		}
	}

	public void close() {
		udaPlugin.close();
	}	
}
