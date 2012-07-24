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

package org.apache.hadoop.mapreduce;

import org.junit.Test;
import static org.junit.Assert.*;
import static org.mockito.Mockito.*;

import org.apache.hadoop.mapred.ShuffleProviderPlugin;
import org.apache.hadoop.mapred.TaskTracker;
import org.apache.hadoop.mapred.TaskController;
import org.apache.hadoop.mapred.JobConf;
import org.apache.hadoop.mapred.JobID;

import org.apache.hadoop.mapred.ShuffleConsumerPlugin;
import org.apache.hadoop.mapred.ReduceTask;
import org.apache.hadoop.mapred.TaskUmbilicalProtocol;
import org.apache.hadoop.mapred.Reporter;
import org.apache.hadoop.fs.LocalFileSystem;


/**
  * A JUnit for testing availability and accessibility of main API that is needed for sub-classes
  * of ShuffleProviderPlugin and ShuffleConsumerPlugin
 */
public class TestShufflePlugin {
	
	@Test
	/**
	 * A method for testing availability and accessibility of API that is needed for sub-classes of ShuffleProviderPlugin
	 */
	public void testProvider() {
		//mock creation
		ShuffleProviderPlugin mockShuffleProvider = mock(ShuffleProviderPlugin.class);
		TaskTracker mockTT = mock(TaskTracker.class);
		TaskController mockTaskController = mock(TaskController.class);
		
		mockShuffleProvider.initialize(mockTT);
		mockShuffleProvider.destroy();
		
		mockTT.getJobConf();
		mockTT.getJobConf(mock(JobID.class));
		mockTT.getIntermediateOutputDir("","","");
		mockTT.getTaskController();
		
		mockTaskController.getRunAsUser(mock(JobConf.class));
	}
	
	@Test
	/**
	 * A method for testing availability and accessibility of API that is needed for sub-classes of ShuffleConsumerPlugin
	 */
	public void testConsumer() {
		//mock creation
		ShuffleConsumerPlugin mockShuffleConsumer = mock(ShuffleConsumerPlugin.class);
		ReduceTask mockReduceTask = mock(ReduceTask.class);
		JobConf mockJobConf = mock(JobConf.class);
		TaskUmbilicalProtocol mockUmbilical = mock(TaskUmbilicalProtocol.class);
		Reporter mockReporter = mock(Reporter.class);
		LocalFileSystem mockLocalFileSystem = mock(LocalFileSystem.class);
		
		mockReduceTask.getTaskID();
		mockReduceTask.getJobID();
		mockReduceTask.getNumMaps();
		mockReduceTask.getPartition();
		mockReduceTask.getJobFile();
		mockReduceTask.getJvmContext();
		
		mockReporter.progress();
		
		try {
			String [] dirs = mockJobConf.getLocalDirs();
			mockShuffleConsumer.init(mockReduceTask, mockUmbilical, mockJobConf, mockReporter);
			mockShuffleConsumer.fetchOutputs();
			mockShuffleConsumer.createKVIterator(mockJobConf, mockLocalFileSystem.getRaw(), mockReporter);
			mockShuffleConsumer.close();
		}
		catch (java.io.IOException e){}
	}
}
