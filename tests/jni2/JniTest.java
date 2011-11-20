class JniTest {
	private static int SIZE = 10;

    private static byte[] arr1, arr2, arr3;
    private static native void initIDs();
    private native void nativeMethod(byte[] arr1, byte[] arr2, byte[] arr3);
	private static void check() {
		for (int i = 0; i < SIZE; ++i)
			if (arr3[i] != (arr1[i] | arr2[i]))
				{ System.out.println("CHECK FAILED: Error at index " + i); return; }
		System.out.println("CHECK OK");
	}
	
    private void callback() {
        System.out.println(">>> In Java callback");
		check();
        System.out.println("<<< Exiting Java callback");
    }
    public static void main(String args[]) {
        System.out.println(">>> In Java main");
        JniTest c = new JniTest();
        c.nativeMethod(arr1, arr2, arr3);
		check();
        System.out.println("<<< Exiting Java main");
    }
    static {
		arr1 = new byte[SIZE];
		arr2 = new byte[SIZE];
		arr3 = new byte[SIZE];
		for (int i = 0; i < SIZE; ++i) {
			arr1[i] = (byte)(i*1);
			arr2[i] = (byte)(i*2);
			arr3[i] = (byte)(i*3);
		}
        System.loadLibrary("JniTest");
        initIDs();
    }
}
