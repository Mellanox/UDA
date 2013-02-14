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

// NOTE: this file should be in shared area.
// It is copied as it to all plugins except 3.x which doesn't need it.
//
// However, currently, itt existentce in shared will break compilation of 
// our hadoop-3.x plugin (unless we change our Makefile sceme)

public class LRUCacheBridge<K, V> extends TaskTracker.LRUCache<K, V> {
    public LRUCacheBridge(int cacheSize) {
			super (cacheSize);
    }
}

