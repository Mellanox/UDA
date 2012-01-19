package org.apache.hadoop.mapred;

import org.apache.commons.logging.Log;
import org.apache.hadoop.util.StringUtils;

interface UdaCallable {
	public void fetchOverMessage();
	public void dataFromUda(Object directBufAsObj, int len);
}

public class UdaBridge {

    static {
        System.loadLibrary("hadoopUda"); //load libhadoopUda.so
    }
	
	static private UdaCallable callable;
	static private Log LOG;
	
    private static native int startNative(boolean isNetMerger, String args[]);
    public static int start(boolean isNetMerger, String args[], Log _LOG, UdaCallable _callable) {
    	LOG = _LOG;
    	callable = _callable;

        LOG.info("UdaBridge: going to execute child thread using args: " + args.toString());    	  
        LOG.info("UdaBridge: going to execute child thread with argc=: " + args.length);    	  
    	LOG.info(" +++>>> invoking UdaBridge.startNative: isNetMerger=" + isNetMerger);
    	int ret = startNative(isNetMerger, args);
    	LOG.info(" <<<+++ after UdaBridge.startNative ret=" + ret);

    	return ret;
    }

    private static native void doCommandNative(String s);
    public static void doCommand(String s) {
		LOG.info(" +++>>> invoking UdaBridge.doCommandNative");
    	doCommandNative(s);
		LOG.info(" <<<+++ after UdaBridge.doCommandNative");
    }

    //NetMerger's callbacks from C++ start here	

	static public void fetchOverMessage() throws Throwable {
		LOG.info("+++>>> started  UdaBridge.fetchOverMessage");
		try{
			callable.fetchOverMessage();
		} 
		catch (Throwable t) {
			LOG.info("!!!+++ failed  UdaBridge.fetchOverMessage: " + t);
			LOG.fatal("!!!+++ failed  UdaBridge.fetchOverMessage: " + t);
            LOG.fatal(StringUtils.stringifyException(t));

			throw (t);  // TODO: consider returning error code to C++
		}
		LOG.info("<<<+++ finished UdaBridge.fetchOverMessage"); 
	}	
	
	static public void dataFromUda(Object directBufAsObj, int len)  throws Throwable {
		LOG.info("+++>>> started  UdaBridge.dataFromUda");
		try{
			callable.dataFromUda(directBufAsObj, len);
		} 
		catch (Throwable t) {
			LOG.info("!!!+++ failed  UdaBridge.dataFromUda: " + t);
			LOG.fatal("!!!+++ failed  UdaBridge.dataFromUda: " + t);
            LOG.fatal(StringUtils.stringifyException(t));
			throw (t);  // TODO: consider returning error code to C++
		}
		LOG.info("<<<+++ finished UdaBridge.dataFromUda"); 
	}	
}
