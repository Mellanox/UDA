package org.apache.hadoop.mapred;

import org.apache.commons.logging.Log;

interface UdaCallable {
	public void fetchOverMessage();
}

public class UdaBridge {

	static private UdaCallable callable;
	static private Log LOG;

	static public void fetchOverMessage() {
		LOG.info("in UdaBridge.fetchOverMessage"); 
		callable.fetchOverMessage();
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
