package org.apache.hadoop.mapred;

import org.apache.commons.logging.Log;
import org.apache.hadoop.util.StringUtils;

interface UdaCallable {
	public void fetchOverMessage();
	public void dataFromUda(Object directBufAsObj, int len);
}

public class UdaBridge {

	static private UdaCallable callable;
	static private Log LOG;

	public static void init(UdaCallable _callable, Log _LOG) {
		callable = _callable;
		LOG = _LOG;
	}
	
    private static native int startNative(String args[], boolean isNetMerger);
    public static int start(String args[], boolean isNetMerger) {
		LOG.info(" +++>>> invoking UdaBridge.startNative: isNetMerger=" + isNetMerger);
		int ret = startNative(args, isNetMerger);
		LOG.info(" <<<+++ after UdaBridge.startNative ret=" + ret);
		return ret;
    }
    
    private static native void doCommandNative(String s);
    public static void doCommand(String s) {
		LOG.info(" +++>>> invoking UdaBridge.doCommandNative");
    	doCommandNative(s);
		LOG.info(" <<<+++ after UdaBridge.doCommandNative");
    }

	/**
	 * @param args
	 */
    public static void main(String args[]) {
    	String[] s  = {"bin/NetMerger", "-c", "9010", "-r", "9011", "-l", "9012", "-a", "2", "-m", "1", "-g", "logs/", "-b", "16383", "-s", "128", "-t", "7"};
        UdaBridge.start(s, true);
    }
    static {
        System.loadLibrary("uda");
    }
	
//callbacks from C++ start here	
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
