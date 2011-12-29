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

	static public void fetchOverMessage() throws Throwable {
		LOG.info("<<<+++ started  UdaBridge.fetchOverMessage");
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

	public static void init(UdaCallable _callable, Log _LOG) {
		callable = _callable;
		LOG = _LOG;
	}
	
    public static native int start(String args[]);
    
    public static native void doCommand(String s);

	/**
	 * @param args
	 */
    public static void main(String args[]) {
    	String[] s  = {"bin/NetMerger", "-c", "9010", "-r", "9011", "-l", "9012", "-a", "2", "-m", "1", "-g", "logs/", "-b", "16383", "-s", "128", "-t", "7"};
        UdaBridge.start(s);
    }
    static {
        System.loadLibrary("uda");
    }
}
