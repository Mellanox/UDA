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

package org.apache.hadoop.mapred;

import java.io.IOException;
import org.apache.hadoop.mapred.JobConf;
import org.apache.hadoop.mapred.Task;
import org.apache.hadoop.mapred.Task.TaskReporter;
import org.apache.hadoop.mapred.ReduceTask.ReduceCopier;
import org.apache.hadoop.util.ReflectionUtils;
import org.apache.hadoop.fs.FileSystem;

public class UdaMapredBridge {
	
	public static ShuffleConsumerPlugin getShuffleConsumerPlugin(Class<? extends ShuffleConsumerPlugin> clazz, ReduceTask reduceTask, 
			TaskUmbilicalProtocol umbilical, JobConf conf, Reporter reporter) throws ClassNotFoundException, IOException  {
	
		ShuffleConsumerPlugin plugin = null;

		if (clazz == null) {
			clazz = ReduceCopier.class;
		}
		if (clazz == ReduceCopier.class) {
			plugin = reduceTask.new ReduceCopier();
		}
		else {			
		  plugin = ReflectionUtils.newInstance(clazz, conf);
		}
		ShuffleConsumerPlugin.Context context = new ShuffleConsumerPlugin.Context(reduceTask, umbilical, conf, (TaskReporter) reporter);
		plugin.init(context);
		return plugin;
	}

}
