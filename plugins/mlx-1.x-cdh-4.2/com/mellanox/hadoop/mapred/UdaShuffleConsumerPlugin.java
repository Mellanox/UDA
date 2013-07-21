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
import org.apache.hadoop.io.IntWritable;
import org.apache.hadoop.mapred.ReduceTask;

public class UdaShuffleConsumerPlugin<K, V> implements ShuffleConsumerPlugin, UdaConsumerPluginCallable{

	UdaShuffleConsumerPluginShared  udaPlugin = new UdaShuffleConsumerPluginShared(this);

  @Override // callback from UdaConsumerPluginCallable
	public RawKeyValueIterator pluginCreateKVIterator(ShuffleConsumerPlugin plugin, JobConf job, FileSystem fs, Reporter reporter)
																										throws IOException, InterruptedException{
		return plugin.createKVIterator();
	}

  @Override // callback from UdaConsumerPluginCallable
	public Class getVanillaPluginClass(){
		return ReduceTask.ReduceCopier.class;
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
	public void init(ShuffleConsumerPlugin.Context context) throws IOException {
		udaPlugin.init(context.getReduceTask(), context.getUmbilical(), context.getJobConf(), context.getReporter());
	}

  @Override
	public boolean fetchOutputs() throws IOException {
		return udaPlugin.fetchOutputs();
	}   

	@Override
	public Throwable getMergeThrowable(){
		return null;
	}

  @Override
	public RawKeyValueIterator createKVIterator() throws IOException {
		FileSystem fs =  FileSystem.getLocal(udaPlugin.jobConf).getRaw(); // Avner: TODO: check
		return udaPlugin.createKVIterator(udaPlugin.jobConf, fs, udaPlugin.reporter);
	}

  @Override
	public void close() {
		udaPlugin.close();
	}

}
