import java.nio.ByteBuffer;

class JniTest {
	private static int SIZE = 1024*1024;

    private static byte[] arr1 = new byte[SIZE];
    private static byte[] arr2 = new byte[SIZE];
    private static byte[] arr3 = new byte[SIZE];
	private static ByteBuffer barr1, barr2, barr3;
    private static native void initIDs();
    private native void nativeMethod();

	private static void check() {
		barr3.rewind();
		barr3.get(arr3);

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
		
        c.nativeMethod();
		
		check();
        System.out.println("<<< Exiting Java main");
    }

    static {	
	
		barr1 = ByteBuffer.allocateDirect(SIZE);
		barr2 = ByteBuffer.allocateDirect(SIZE);
		barr3 = ByteBuffer.allocateDirect(SIZE);

/*
		java.nio.ByteOrder bo = java.nio.ByteOrder.nativeOrder();
//		java.nio.ByteOrder bo = java.nio.ByteOrder.BIG_ENDIAN;
//		java.nio.ByteOrder bo = java.nio.ByteOrder.LITTLE_ENDIAN;
		barr1.order(bo);
		barr2.order(bo);
		barr3.order(bo);
		
		arr1 = barr1.array();
		arr2 = barr2.array();
		arr3 = barr3.array();
//*/		

		for (int i = 0; i < SIZE; ++i) arr1[i] = (byte)(i*1);
		for (int i = 0; i < SIZE; ++i) arr2[i] = (byte)(i*2);
		for (int i = 0; i < SIZE; ++i) arr3[i] = (byte)(i*3);
		barr1.put(arr1);
		barr2.put(arr2);
		barr3.put(arr3);
		
        System.loadLibrary("JniTest");
        initIDs();
    }
}
