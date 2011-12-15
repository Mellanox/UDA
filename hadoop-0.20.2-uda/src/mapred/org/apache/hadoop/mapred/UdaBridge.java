package org.apache.hadoop.mapred;


public class UdaBridge {

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
