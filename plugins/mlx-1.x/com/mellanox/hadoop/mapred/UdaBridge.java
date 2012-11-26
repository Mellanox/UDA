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
import org.apache.hadoop.mapred.*;

import java.util.ArrayList;
import java.util.List;

import org.apache.commons.logging.Log;
import org.apache.hadoop.util.StringUtils;

interface UdaCallable {
	public void fetchOverMessage();
	public void dataFromUda(Object directBufAsObj, int len) throws Throwable;
}

public class UdaBridge {

    static {  
		String s1=UdaBridge.class.getProtectionDomain().getCodeSource().getLocation().getPath(); 
		String s2=s1.substring(0, s1.lastIndexOf("/")+1); // /usr/lib64/uda/
		Runtime.getRuntime().load(s2+"libuda.so");
    }
	
	static private UdaCallable callable;
	static private Log LOG;

	// Native methods and their wrappers start here
	
	private static native int startNative(boolean isNetMerger, String args[]);
	static void start(boolean isNetMerger, String[] args, Log _LOG, UdaCallable _callable) {
		LOG = _LOG;
		callable = _callable;

		LOG.info(" +++>>> invoking UdaBridge.startNative: isNetMerger=" + isNetMerger);
		int ret = startNative(isNetMerger, args);
		LOG.info(" <<<+++ after UdaBridge.startNative ret=" + ret);
	}
	
	
    private static native void doCommandNative(String s);
    public static void doCommand(String s) {
    	if (LOG.isDebugEnabled()) LOG.debug(" +++>>> invoking UdaBridge.doCommandNative");
    	doCommandNative(s);
    	if (LOG.isDebugEnabled()) LOG.debug(" <<<+++ after UdaBridge.doCommandNative");
    }

    //callbacks from C++ start here	

	static public void fetchOverMessage() throws Throwable {
		if (LOG.isDebugEnabled()) LOG.debug("+++>>> started  UdaBridge.fetchOverMessage");
		callable.fetchOverMessage();
		if (LOG.isDebugEnabled()) LOG.debug("<<<+++ finished UdaBridge.fetchOverMessage"); 
	}	
	
	static public void dataFromUda(Object directBufAsObj, int len)  throws Throwable {
		if (LOG.isDebugEnabled()) LOG.debug("+++>>> started  UdaBridge.dataFromUda");
		callable.dataFromUda(directBufAsObj, len);
		if (LOG.isDebugEnabled()) LOG.debug("<<<+++ finished UdaBridge.dataFromUda"); 
	}	
	
	static public Object getPathUda(String jobId, String mapId, int reduceId)  {
		if (LOG.isDebugEnabled()) LOG.debug("+++>>> started  UdaBridge.getPathUda");
    	//String s = callable.getPath(jobId, mapId, reduceId);//return "katya";
		DataPassToJni d = UdaPluginTT.getPathIndex(jobId, mapId, reduceId);//return "katya";
		return d;
	}	
	
	static public String getConfData(String paramName,String defaultParam)  {
		if (LOG.isDebugEnabled()) LOG.debug("+++>>> started  UdaBridge.getConfData");
		String data = UdaPluginRT.getDataFromConf(paramName,defaultParam);
		return data;
	}
	
}

class DataPassToJni{
	  long startOffset;
	  long rawLength;
	  long partLength;
	  String pathMOF;
}