package com.mellanox.hadoop.mapred;

import java.lang.reflect.Constructor;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;

public class Utils {

	/**
	 * looks for method in class, invokes it and return it's result
	 * @param classToSearch what class to search
	 * @param methodName what method to search
	 * @param argsClass array of the method arguments class types
	 * @param classInst instance of the class
	 * @param args argument to pass to the method
	 * @return the method result or null on error
	 */
	   public static Object invokeFunctionReflection (Class classToSearch, String methodName, Class[] argsClass, Object classInst, Object[] args) {

		   Method func = null;

		   if ((func = getFunctionReflection (classToSearch, methodName, argsClass)) == null) {
			   return null;
		   }

		   try {
			   Object ret = func.invoke(classInst, args);
			   return ret;
			} catch (Exception e) {
				throw new UdaRuntimeException("Could not invoke function", e);
			}
	   }

	   /**
	    * Helper func for finding method with right signature in a class
	    */
	   private static Method getFunctionReflection (Class classToSearch, String methodName, Class[] args){

		   try
		   {
			   Method func = classToSearch.getDeclaredMethod(methodName, args);
			   return func;
		   } catch(NoSuchMethodException e1) {
		    	UdaShuffleConsumerPluginShared.LOG.trace("didn't find method "+methodName+ " in class "+classToSearch.getName());
		   }

		   return null;
	   }

	   /**
	    * invoke constructor of a class and return new instance
	    * @param classToSearch what class to search
	    * @param argsClass array of the ctor arguments class types
	    * @param args argument to pass to the method
	    * @return new instance of the class on null on error
	    */
	   public static Object invokeConstructorReflection(Class classToSearch, Class[] argsClass, Object[] args) {

		   try {
			    Constructor ctor = classToSearch.getConstructor(argsClass);
				return createCtorInst(ctor, args);
			} catch (Exception e) {
				UdaShuffleConsumerPluginShared.LOG.trace("Could not find constructor in class "+classToSearch.getName());
			}

		   return null;
	   }

	   /**
	    * Helper func for creating new instance of a class
	    */
	   private static Object createCtorInst(Constructor constructor, Object[] args) {

		    try {
		    	Object obj = constructor.newInstance(args);
		    	return obj;
		    } catch (Exception e) {
		    	throw new UdaRuntimeException("Could not create constructor instance", e);
		    }
	   }

	   /**
	    * create new instance of a class using a constructor that receives 1 argument
	    * @param classToInvoke
	    * @param argClass the class of the argument to pass the constructor
	    * @param argInst instance of the outer class to pass to the constructor of the inner
	    * @return new instance or null on failure
	    */
	   public static Object invokeCtorWithArg (Class classToInvoke, Class argClass,  Object argInst) {
		   try {
				Constructor ctor = classToInvoke.getDeclaredConstructor(argClass);
				try {
					ctor.setAccessible(true);
					return ctor.newInstance(argInst);
				} catch (Exception e) {
					throw new UdaRuntimeException("Could not create inner constructor instance", e);
				}
			} catch (Exception e) {
				UdaShuffleConsumerPluginShared.LOG.trace("Could not find constructor of class "+classToInvoke.getName()+" that recieves arg of type "+argClass.getName());
			}
		   return null;
	   }
}
