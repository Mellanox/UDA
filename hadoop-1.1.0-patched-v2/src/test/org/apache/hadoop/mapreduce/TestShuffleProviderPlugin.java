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


import static org.junit.Assert.*;
import org.apache.hadoop.mapred.TaskTracker;
import org.apache.hadoop.mapred.JobID;
import org.apache.hadoop.mapred.ShuffleProviderPlugin;
import org.junit.Test;
import static org.mockito.Mockito.*;



public class TestShuffleProviderPlugin implements ShuffleProviderPlugin {

  public void initialize(TaskTracker tt){
  }
	
  public void destroy(){
  }

	
  @Test
  /*Testing that ShuffleProviderPlugin interface exists  
  */
  public void testInterface() {
	ShuffleProviderPlugin spp = (ShuffleProviderPlugin)this;
	TaskTracker tt = mock(TaskTracker.class);
	spp.initialize(tt);
	spp.destroy();
  }	
	
  @Test
  /*Testing that TaskTracker's methods which are used by ShuffleProviderPlugin
  exist and they are public  
  */
  public void testAPI() {
	TaskTracker tt = mock(TaskTracker.class);
	JobID mockjobId = mock(JobID.class);
	
	tt.getJobConf();
	tt.getJobConf(mockjobId);	
	tt.getIntermediateOutputDir("","","");
  }

}
