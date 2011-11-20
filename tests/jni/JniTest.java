class JniTest {
    private static native void initIDs();
    private native void nativeMethod();
    private void callback() {
        System.out.println("In Java");
    }
    public static void main(String args[]) {
        JniTest c = new JniTest();
        c.nativeMethod();
    }
    static {
        System.loadLibrary("JniTest");
        initIDs();
    }
}
