package org.apache.hadoop.mapred;

class JniTest {
    private static native void initIDs();
    private native void nativeMethod();
    static private void staticCallback() {
        System.out.println("In Java static callback");
    }
    private void callback() {
        System.out.println("In Java callback");
    }
    public static void main(String args[]) {
        JniTest c = new JniTest();
        c.nativeMethod();
    }
    static {
        System.out.println("--->>> Java Loaded");
        System.loadLibrary("JniTest");
        System.out.println("--->>> In Java: native library was loaded");
        initIDs();
    }
}
