/*
** Copyright (C) 2012 Auburn University
** Copyright (C) 2012 Mellanox Technologies
** 
** Licensed under the Apache License, Version 2.0 (the "License");
** you may not use this file except in compliance with the License.
** You may obtain a copy of the License at:
**  
** http://www.apache.org/licenses/LICENSE-2.0
** 
** Unless required by applicable law or agreed to in writing, software
** distributed under the License is distributed on an "AS IS" BASIS,
** WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, 
** either express or implied. See the License for the specific language 
** governing permissions and  limitations under the License.
**
**
*/
package com.mellanox.hadoop.mapred;

import org.apache.hadoop.mapred.*;

import java.io.File;
import java.io.IOException;
import java.lang.management.MemoryType;
import java.lang.management.MemoryUsage;
import java.lang.reflect.Type;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.Vector;
import java.util.logging.MemoryHandler;
import java.util.Map.Entry;

import org.apache.hadoop.mapred.Reporter;

import org.apache.hadoop.util.Progress;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.LocalDirAllocator;
import org.apache.hadoop.io.DataInputBuffer;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;

import org.apache.hadoop.util.StringUtils;
import org.apache.hadoop.util.DiskChecker;
import org.apache.hadoop.util.DiskChecker.DiskErrorException;
import org.apache.hadoop.io.WritableUtils;

import org.apache.hadoop.fs.Path;

import java.util.Timer;
import java.util.TimerTask;



abstract class UdaPlugin {
	protected List<String> mCmdParams = new ArrayList<String>();
	protected static Log LOG;
	protected static int log_level = -1; // Initialisation value for calcAndCompareLogLevel() first run
	protected static JobConf mjobConf;
	
	public UdaPlugin(JobConf jobConf) {
		this.mjobConf=jobConf;
	}
	
	//* build arguments to lunchCppSide 
	protected abstract void buildCmdParams();

	
	//* sets the logger properly as configured in log4j conf file
	private static void setLog(String logging_name){
		LOG = LogFactory.getLog(logging_name);
	}
	
	//* retrieves and sets the logging level, if log_level was changed return true, else return false.
	private static boolean calcAndCompareLogLevel(){
		int curr_log_level = (LOG.isFatalEnabled() ? 1 : 0) + (LOG.isErrorEnabled() ? 1 : 0) +  
						 	 (LOG.isWarnEnabled() ? 1 : 0) +(LOG.isInfoEnabled() ? 1 : 0) + 
						 	 (LOG.isDebugEnabled() ? 1 : 0) + (LOG.isTraceEnabled() ? 1 : 0);
		if(curr_log_level == log_level)
			return false;
		else
		{
			log_level = curr_log_level;
			return true;
		}
	}
	
	//* configuring all that is needed for logging
	protected static void prepareLog(String logging_name){
		setLog(logging_name);
		calcAndCompareLogLevel();	
		}
	
	protected void launchCppSide(boolean isNetMerger, UdaCallable _callable) {
		
		
		//only if this is the provider, start the periodic log check task.
		if(!isNetMerger)
		{
			LOG.debug("starting periodic log check task");
			Timer timer = new Timer();
			timer.schedule(new TaskLogLevel(), 0, 1000);
		}
		
		LOG.debug("Launching C++ thru JNI");
		buildCmdParams();

		LOG.info("going to execute C++ thru JNI with argc=: " + mCmdParams.size() + " cmd: " + mCmdParams);    	  
		String[] stringarray = mCmdParams.toArray(new String[0]);
		
		// if parameter is set to "true", UDA will log into its own files.
		Boolean log_to_uda_file = mjobConf.getBoolean("mapred.uda.log.to.unique.file", false);

		try {
			UdaBridge.start(isNetMerger, stringarray, LOG, log_level, log_to_uda_file, _callable);

		} catch (UnsatisfiedLinkError e) {
			LOG.warn("UDA: Exception when launching child");    	  
			LOG.warn("java.library.path=" + System.getProperty("java.library.path"));
			LOG.warn(StringUtils.stringifyException(e));
			throw (e);
		}
	}
	
	// Class represents the period task of log-level checking & setting in C++ 
	class TaskLogLevel extends TimerTask{
		public void run()
		{
			// check if log level has changed
			if(calcAndCompareLogLevel())
			{
				// set log level in C++
				UdaBridge.setLogLevel(log_level);
				LOG.info("Logging level was cahanged");
			}
		}
	}

}

class UdaPluginRT<K,V> extends UdaPlugin implements UdaCallable {

	static{
		prepareLog(ShuffleConsumerPlugin.class.getCanonicalName());
	}
	
	final UdaShuffleConsumerPluginShared udaShuffleConsumer;
	final ReduceTask reduceTask;

	private Reporter      mTaskReporter = null;    
	private Progress          mProgress     = null;
	private Vector<String>    mParams       = new Vector<String>();
	private int               mMapsNeed     = 0;      
	private int               mMapsCount    = 0; // we probably can remove this var
	private int               mReqNums      = 0;
	private final int         mReportCount  = 20;
	private J2CQueue<K,V>     j2c_queue     = null;

	//* kv buf status 
	private final int         kv_buf_recv_ready = 1;
	private final int         kv_buf_redc_ready = 2;
	//* kv buf related vars  
	private final int         kv_buf_size = 1 << 20;   /* 1 MB */
	private final int         kv_buf_num = 2;
	private KVBuf[]           kv_bufs = null;
	
	private final static float 	  DEFAULT_SHUFFLE_INPUT_PERCENT = 0.7f;

	private void init_kv_bufs() {
		kv_bufs = new KVBuf[kv_buf_num];
		for (int idx = 0; idx < kv_buf_num; ++idx) {
			kv_bufs[idx] = new KVBuf(kv_buf_size);
		} 
	}

	protected void buildCmdParams() {
		mCmdParams.clear();
		
		mCmdParams.add("-w");
		mCmdParams.add(mjobConf.get("mapred.rdma.wqe.per.conn", "256"));
		mCmdParams.add("-r");
		mCmdParams.add(mjobConf.get("mapred.rdma.cma.port", "9011"));      
		mCmdParams.add("-a");
		mCmdParams.add(mjobConf.get("mapred.netmerger.merge.approach", "1"));
		mCmdParams.add("-m");
		mCmdParams.add("1");
		
		String s1 = TaskLog.getTaskLogFile(reduceTask.getTaskID(), false, TaskLog.LogName.STDOUT).toString(); //userlogs/job_201208301702_0002/attempt_201208301702_0002_r_000002_0/stdout
		String s2=s1.substring(0, s1.lastIndexOf("/")+1);
		mCmdParams.add("-g");
		mCmdParams.add(s2);
		
		mCmdParams.add("-s");
		mCmdParams.add(mjobConf.get("mapred.rdma.buf.size", "1024"));
		
	}

	public UdaPluginRT(UdaShuffleConsumerPluginShared udaShuffleConsumer, ReduceTask reduceTask, JobConf jobConf, Reporter reporter,
			int numMaps) throws IOException {
		super(jobConf);
		this.udaShuffleConsumer = udaShuffleConsumer;
		this.reduceTask = reduceTask;
		
		String totalRdmaSizeStr = jobConf.get("mapred.rdma.shuffle.total.size", "0"); // default 0 means ignoring this parameter and use instead -Xmx and mapred.job.shuffle.input.buffer.percent
		long totalRdmaSize = StringUtils.TraditionalBinaryPrefix.string2long(totalRdmaSizeStr);
		long maxRdmaBufferSize= jobConf.getLong("mapred.rdma.buf.size", 1024);
		long minRdmaBufferSize=jobConf.getLong("mapred.rdma.buf.size.min", 16);
		long shuffleMemorySize = totalRdmaSize;
		StringBuilder meminfoSb = new StringBuilder();
		meminfoSb.append("UDA: numMaps=").append(numMaps);
		meminfoSb.append(", maxRdmaBufferSize=").append(maxRdmaBufferSize);
		meminfoSb.append("KB, minRdmaBufferSize=").append(minRdmaBufferSize).append("KB");
		meminfoSb.append("KB, rdmaShuffleTotalSize=").append(totalRdmaSize);
		
		if (totalRdmaSize < 0) {
			LOG.warn("Illegal paramter value: mapred.rdma.shuffle.total.size=" +  totalRdmaSize);
		}

		if (totalRdmaSize <= 0) {	
			long maxHeapSize = Runtime.getRuntime().maxMemory();
			double shuffleInputBufferPercent = jobConf.getFloat("mapred.job.shuffle.input.buffer.percent", DEFAULT_SHUFFLE_INPUT_PERCENT);
			if ((shuffleInputBufferPercent < 0) || (shuffleInputBufferPercent > 1)) {
				LOG.warn("UDA: mapred.job.shuffle.input.buffer.percent is out of range - set to default: " + DEFAULT_SHUFFLE_INPUT_PERCENT);
				shuffleInputBufferPercent = DEFAULT_SHUFFLE_INPUT_PERCENT;
			}
			shuffleMemorySize = (long)(maxHeapSize * shuffleInputBufferPercent);
			
			LOG.info("Using JAVA Xmx with mapred.job.shuffle.input.buffer.percent to limit UDA shuffle memory");
				
			meminfoSb.append(", maxHeapSize=").append(maxHeapSize).append("B");
			meminfoSb.append(", shuffleInputBufferPercent=").append(shuffleInputBufferPercent);			
			meminfoSb.append("==> shuffleMemorySize=").append(shuffleMemorySize).append("B");
			
			LOG.info("RDMA shuffle memory is limited to " + shuffleMemorySize/1024/1024 + "MB");
		} 
		else {
			LOG.info("Using mapred.rdma.shuffle.total.size to limit UDA shuffle memory");
			LOG.info("RDMA shuffle memory is limited to " + totalRdmaSize/1024/1024 + "MB");
		}
		
		LOG.debug(meminfoSb.toString());
		LOG.info("UDA: user prefer rdma.buf.size=" + maxRdmaBufferSize + "KB");
		LOG.info("UDA: minimum rdma.buf.size=" + minRdmaBufferSize + "KB");

		if(jobConf.getSpeculativeExecution()) { // (getMapSpeculativeExecution() || getReduceSpeculativeExecution())
			LOG.info("UDA has limited support for map task speculative execution");
		}
		
		LOG.info("UDA: number of segments to fetch: " + numMaps);
		
		/* init variables */
		init_kv_bufs(); 
		
		launchCppSide(true, this); // true: this is RT => we should execute NetMerger

		this.j2c_queue = new J2CQueue<K, V>();
		this.mTaskReporter = reporter;
		this.mMapsNeed = numMaps;


		/* send init message */
		TaskAttemptID reduceId = reduceTask.getTaskID();

		mParams.clear();
		mParams.add(Integer.toString(numMaps));
		mParams.add(reduceId.getJobID().toString());
		mParams.add(reduceId.toString());
		mParams.add(jobConf.get("mapred.netmerger.hybrid.lpq.size", "0"));
		mParams.add(Long.toString(maxRdmaBufferSize * 1024)); // in Bytes - pass the raw value we got from xml file (with only conversion to bytes)
		mParams.add(Long.toString(minRdmaBufferSize * 1024)); // in Bytes . passed for checking if rdmaBuffer is still larger than minRdmaBuffer after alignment			 
		mParams.add(jobConf.getOutputKeyClass().getName());
		
		boolean compression = jobConf.getCompressMapOutput(); //"true" or "false"
		String alg =null;
        if(compression){
            alg = jobConf.get("mapred.map.output.compression.codec", null);
		}
		mParams.add(alg); 
		
		String bufferSize=Integer.toString(256*1024);		
		if(alg!=null){
             if(alg.contains("lzo.LzoCodec")){
                bufferSize = jobConf.get("io.compression.codec.lzo.buffersize", bufferSize);
            }else if(alg.contains("SnappyCodec")){
                bufferSize = jobConf.get("io.compression.codec.snappy.buffersize", bufferSize);
            }
        }		
		mParams.add(bufferSize);
		mParams.add(Long.toString(shuffleMemorySize));
	
		String [] dirs = jobConf.getLocalDirs();
		ArrayList<String> dirsCanBeCreated = new ArrayList<String>();
		//checking if the directories can be created
		for (int i=0; i<dirs.length; i++ ){
			try {
				DiskChecker.checkDir(new File(dirs[i].trim()));
				//saving only the directories that can be created
				dirsCanBeCreated.add(dirs[i].trim());
			} catch(DiskErrorException e) {  }
		}
		//sending the directories
		int numDirs = dirsCanBeCreated.size();
		mParams.add(Integer.toString(numDirs));
		for (int i=0; i<numDirs; i++ ){
			mParams.add(dirsCanBeCreated.get(i));
		}

		LOG.info("mParams array is " + mParams);
		LOG.info("UDA: sending INIT_COMMAND");    	  
		String msg = UdaCmd.formCmd(UdaCmd.INIT_COMMAND, mParams);
		UdaBridge.doCommand(msg);
		this.mProgress = new Progress(); 
		this.mProgress.set(0.5f);
	}

//	public void sendFetchReq (MapOutputLocation loc) {
	public void sendFetchReq (String host, String jobID, String TaskAttemptID) {
		/* "host:jobid:mapid:reduce" */
		mParams.clear();
		mParams.add(host);
		mParams.add(jobID);
		mParams.add(TaskAttemptID);
//		mParams.add(loc.getHost());
//		mParams.add(loc.getTaskAttemptId().getJobID().toString());
//		mParams.add(loc.getTaskAttemptId().toString());
		mParams.add(Integer.toString(reduceTask.getPartition()));
		String msg = UdaCmd.formCmd(UdaCmd.FETCH_COMMAND, mParams); 
		UdaBridge.doCommand(msg);
	}

	public void close() {
		LOG.info("sending EXIT_COMMAND by calling reduceExitMsg...");    	  
		UdaBridge.reduceExitMsg();
    	if (LOG.isDebugEnabled()) LOG.debug(">> C++ finished.  Closing java...");
		this.j2c_queue.close();
    	if (LOG.isDebugEnabled()) LOG.debug("<< java finished");
	}

	public <K extends Object, V extends Object>
	RawKeyValueIterator createKVIterator_rdma(JobConf job, FileSystem fs, Reporter reporter) {
		this.j2c_queue.initialize();
		return this.j2c_queue; 
	}

	// callback from C++
	public void fetchOverMessage() {
		if (LOG.isDebugEnabled()) LOG.debug(">> in fetchOverMessage"); 
		mMapsCount += mReportCount;
		if (mMapsCount >= this.mMapsNeed) mMapsCount = this.mMapsNeed;
		mTaskReporter.progress();
		if (LOG.isInfoEnabled()) LOG.info("in fetchOverMessage: mMapsCount=" + mMapsCount + " mMapsNeed=" + mMapsNeed); 

		if (mMapsCount >= this.mMapsNeed) {
			/* wake up UdaShuffleConsumerPlugin */
			if (LOG.isInfoEnabled()) LOG.info("fetchOverMessage: reached desired num of maps, waking up UdaShuffleConsumerPlugin"); 
				udaShuffleConsumer.notifyFetchCompleted();
		}
		if (LOG.isDebugEnabled()) LOG.debug("<< out fetchOverMessage"); 
	}


	// callback from C++
	int __cur_kv_idx__ = 0;
	public void dataFromUda(Object directBufAsObj, int len) throws Throwable {
		if (LOG.isDebugEnabled()) LOG.debug ("-->> dataFromUda len=" + len);

		KVBuf buf = kv_bufs[__cur_kv_idx__];

		synchronized (buf) {
			while (buf.status != kv_buf_recv_ready) {
				try{
					buf.wait();
				} catch (InterruptedException e) {}
			}

			buf.act_len = len;  // set merged size
			try {
				java.nio.ByteBuffer directBuf = (java.nio.ByteBuffer) directBufAsObj;
				directBuf.position(0); // reset read position 		  
				directBuf.get(buf.kv_buf, 0, len);// memcpy from direct buf into java buf - TODO: try zero-copy
			} catch (Throwable t) {
				LOG.error ("!!! !! dataFromUda GOT Exception");
				LOG.error(StringUtils.stringifyException(t));
				throw (t);
			}

			buf.kv.reset(buf.kv_buf, 0, len); // reset KV read position

			buf.status = kv_buf_redc_ready;
			++__cur_kv_idx__;
			if (__cur_kv_idx__ >= kv_buf_num) {
				__cur_kv_idx__ = 0;
			}
			buf.notifyAll();
		}
		if (LOG.isDebugEnabled()) LOG.debug ("<<-- dataFromUda finished callback");
	}

	/**
	 * gets property paramName from configuration file
	 */
	static String getDataFromConf(String paramName, String defaultParam){
		return mjobConf.get(paramName,defaultParam);
	}

	// callback from C++
	public void failureInUda(){
		udaShuffleConsumer.failureInUda(new UdaRuntimeException("Uda Failure in a C++ thread"));		
	}

	
	
	/* kv buf object, j2c_queue uses 
 the kv object inside.
	 */
	private class KVBuf<K, V> {
		private byte[] kv_buf;
		private int act_len;
		private int status;        
		public DataInputBuffer kv;

		public KVBuf(int size) {
			kv_buf = new byte[size];
			kv = new DataInputBuffer();
			kv.reset(kv_buf,0);
			status = kv_buf_recv_ready;
		}
	}

	private class J2CQueue<K extends Object, V extends Object> 
	implements RawKeyValueIterator {  

		private int  key_len;
		private int  val_len;
		private int  cur_kv_idx;
		private int  cur_dat_len;
		private int  time_count;
		private DataInputBuffer key;
		private DataInputBuffer val;
		private DataInputBuffer cur_kv = null;

		public J2CQueue() {
			cur_kv_idx = -1;
			cur_dat_len= 0;
			key_len  = 0;
			val_len  = 0;
			key = new DataInputBuffer();
			val = new DataInputBuffer();
		} 

		private boolean move_to_next_kv() {
			if (cur_kv_idx >= 0) {
				KVBuf finished_buf = kv_bufs[cur_kv_idx];
				synchronized (finished_buf) {
					finished_buf.status = kv_buf_recv_ready;
					finished_buf.notifyAll();
				}
			}

			++cur_kv_idx;
			if (cur_kv_idx >= kv_buf_num) {
				cur_kv_idx = 0;
			}
			KVBuf next_buf = kv_bufs[cur_kv_idx];

			try { 
				synchronized (next_buf) {
					if (next_buf.status != kv_buf_redc_ready) {
						next_buf.wait();
					}
					cur_kv = next_buf.kv;
					cur_dat_len = next_buf.act_len;
					key_len = 0;
					val_len = 0;
				} 
			} catch (InterruptedException e) {
			}
			return true;
		}

		public void initialize() {
			time_count = 0;
		} 

		public DataInputBuffer getKey() {
			return key;
		}

		public DataInputBuffer getValue() {
			return val;
		}

		public boolean next() throws IOException {
			if (key_len < 0 || val_len < 0) {
				return false;
			}        

			if (cur_kv == null
					|| cur_kv.getPosition() >= (cur_dat_len - 1)) {
				move_to_next_kv(); 
			}  

			if (time_count > 1000) {
				mTaskReporter.progress();
				time_count = 0;
			}
			time_count++; 

			try {
				key_len = WritableUtils.readVInt(cur_kv);
				val_len = WritableUtils.readVInt(cur_kv); 
			} catch (java.io.EOFException e) {
				return false;
			}

			if (key_len < 0 || val_len < 0) {
				return false;
			}

			/* get key */
			this.key.reset(cur_kv.getData(), 
					cur_kv.getPosition(), 
					key_len);
			cur_kv.skip(key_len);

			//* get val
			this.val.reset(cur_kv.getData(), 
					cur_kv.getPosition(), 
					val_len);
			cur_kv.skip(val_len);

			return true;
		}

		public void close() {
			for (int i = 0; i < kv_buf_num; ++i) {
				KVBuf buf = kv_bufs[i];
				if (LOG.isTraceEnabled()) LOG.trace(">>> before synchronized on kv_bufs #" + i);
				synchronized (buf) {
					buf.notifyAll();
				}
				if (LOG.isTraceEnabled()) LOG.trace("<<< after  synchronized on kv_bufs #" + i);
			}
		}

		public Progress getProgress() {
			return mProgress;
		}

	}
}





class UdaCmd {

	public static final int EXIT_COMMAND        = 0; 
	public static final int NEW_MAP_COMMAND     = 1;
	public static final int FINAL_MERGE_COMMAND = 2;  
	public static final int RESULT_COMMAND      = 3;
	public static final int FETCH_COMMAND       = 4;
	public static final int FETCH_OVER_COMMAND  = 5;
	public static final int JOB_OVER_COMMAND    = 6;
	public static final int INIT_COMMAND        = 7;
	public static final int MORE_COMMAND        = 8;
	public static final int NETLEV_REDUCE_LAUNCHED = 9;
	private static final char SEPARATOR         = ':';

	/* num:cmd:param1:param2... */
	public static String formCmd(int cmd, List<String> params) {

		int size = params.size() + 1;
		String ret = "" + size + SEPARATOR + cmd;
		for (int i = 0; i < params.size(); ++i) {
			ret += SEPARATOR;
			ret += params.get(i);
		}
		return ret;
	}
}

