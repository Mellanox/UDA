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

/**
 * This interface is implemented by objects that are able to answer shuffle requests which are
 * sent from a matching Shuffle Consumer that lives in context of a ReduceTask object.
 * 
 * ShuffleProviderPlugin object will be notified on the following events: 
 * initialize, destroy.
 * At this phase, at most one optional ShuffleProvider is supported by TaskTracker 
 * At this phase, TaskTracker will use the optional ShuffleProvider (if any) in addition to 
 * the default shuffle provider (MapOutputServlet).
 * 
 * NOTE: This interface is also used when loading 3rd party plugins at runtime
 *
 */
public interface ShuffleProviderPlugin {
	/**
	 * Do the real constructor work here.  It's in a separate method
	 * so we can call it again and "recycle" the object after calling
	 * destroy().
	 * 
	 * invoked from TaskTracker.initialize
	 */
	public void initialize(TaskTracker taskTracker);
	
	/**
	 * close and cleanup any resource, including threads and disk space.  
	 * A new object within the same process space might be restarted, 
	 * so everything must be clean.
	 * 
	 * invoked from TaskTracker.close
	 */
	public void destroy();	
}
