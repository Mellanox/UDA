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

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.hadoop.mapred.JobConf;
import org.apache.hadoop.mapred.Task.TaskReporter;
import org.apache.hadoop.mapred.ReduceTask;
import org.apache.hadoop.util.ReflectionUtils;

import com.mellanox.hadoop.mapred.UdaRuntimeException;
import com.mellanox.hadoop.mapred.Utils;

public class UdaMapredBridge {

	static final Log LOG = LogFactory.getLog(ShuffleConsumerPlugin.class.getCanonicalName());

	public static ShuffleConsumerPlugin getShuffleConsumerPlugin(Class<? extends ShuffleConsumerPlugin> clazz, ReduceTask reduceTask,
			TaskUmbilicalProtocol umbilical, JobConf conf, Reporter reporter) throws ClassNotFoundException, IOException  {

		String type="vanilla";

		if (clazz == null) {
			clazz = ReduceTask.ReduceCopier.class;
		}
		ShuffleConsumerPlugin plugin = ReflectionUtils.newInstance(clazz, conf);
		ShuffleConsumerPlugin.Context context;

		// 1st - try loading the method according to its vanilla signature
		context = (ShuffleConsumerPlugin.Context)Utils.invokeConstructorReflection(ShuffleConsumerPlugin.Context.class,
						new Class[] {ReduceTask.class, TaskUmbilicalProtocol.class, JobConf.class, TaskReporter.class}, new Object[] {reduceTask, umbilical, conf, (TaskReporter) reporter});
		// if failed - this is probably CDH => try loading the method according to its CDH signature
		if (context == null) {
			type="cdh";
			context = (ShuffleConsumerPlugin.Context)Utils.invokeConstructorReflection(ShuffleConsumerPlugin.Context.class,
					new Class[] {TaskUmbilicalProtocol.class, JobConf.class, TaskReporter.class, ReduceTask.class}, new Object[] {umbilical, conf, (TaskReporter) reporter, reduceTask});
		}

		// still failed => we can't help
		if( context == null) {
			throw new UdaRuntimeException("could not create new instance of ShuffleConsumerPlugin.Context, not when ising its vanilla signature neither when using its CDH signature");
		}

		LOG.info("creating ShuffleConsumerPlugin.Context with "+type+" signature");

		plugin.init(context);
		return plugin;
	}
}
