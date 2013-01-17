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
package com.mellanox.hadoop.mapred;

import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.LinkedList;
import java.util.Map;
import java.util.Map.Entry;


//copied as is from TaskTracker.java
class LRUHash<K, V> {
    private int cacheSize;
    private LinkedHashMap<K, V> map;
	
    public LRUHash(int cacheSize) {
      this.cacheSize = cacheSize;
      this.map = new LinkedHashMap<K, V>(cacheSize, 0.75f, true) {
          protected boolean removeEldestEntry(Map.Entry<K, V> eldest) {
	    return size() > LRUHash.this.cacheSize;
	  }
      };
    }
	
    public synchronized V get(K key) {
      return map.get(key);
    }
	
    public synchronized void put(K key, V value) {
      map.put(key, value);
    }
	
    public synchronized int size() {
      return map.size();
    }
	
    public Iterator<Entry<K, V>> getIterator() {
      return new LinkedList<Entry<K, V>>(map.entrySet()).iterator();
    }
   
    public synchronized void clear() {
      map.clear();
    }
  }

