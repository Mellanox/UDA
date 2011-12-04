package org.apache.hadoop.mapred;


public class UdaLoader {

    public static native int start(String args[]);
	/**
	 * @param args
	 */
    public static void main(String args[]) {
    	String[] s  = {"bin/NetMerger", "-c", "9010", "-r", "9011", "-l", "9012", "-a", "2", "-m", "1", "-g", "logs/", "-b", "16383", "-s", "128", "-t", "7"};
        UdaLoader.start(s);
    }
    static {
        System.loadLibrary("uda");
/*        
        System.loadLibrary("rdmacm");
        System.loadLibrary("ibverbs");
        
        System.loadLibrary("pthread");
        System.loadLibrary("aio");
//*/        
    }
}
