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
        System.loadLibrary("hadoopUda"); //load libhadoopUda.so
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

    //NetMerger's callbacks from C++ start here	

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
}
