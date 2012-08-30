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

