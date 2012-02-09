package org.apache.hadoop.mapred;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Vector;

import org.apache.hadoop.mapred.ReduceTask.ReduceCopier;
import org.apache.hadoop.mapred.ReduceTask.ReduceCopier.MapOutputLocation;
import org.apache.hadoop.mapred.Task.TaskReporter;
import org.apache.hadoop.util.Progress;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.io.DataInputBuffer;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;

import org.apache.hadoop.util.StringUtils;
import org.apache.hadoop.util.DiskChecker;
import org.apache.hadoop.util.DiskChecker.DiskErrorException;
import org.apache.hadoop.io.WritableUtils;

import org.apache.hadoop.fs.Path;

abstract class UdaPlugin {
	static protected final Log LOG = LogFactory.getLog(UdaPlugin.class.getName());

	protected void launchCppSide(boolean isNetMerger, JobConf jobConf, UdaCallable _callable, String logdirTail) {
		
		LOG.info("UDA: Launching C++ thru JNI");
		List<String> cmd = new ArrayList<String>();

		// TODO: remove from conf: "mapred.tasktracker.rdma.server.port", 9010
		
		//* arguments 
		cmd.add("-w");
		cmd.add(jobConf.get("mapred.rdma.wqe.per.conn"));
		cmd.add("-r");
		cmd.add(jobConf.get("mapred.rdma.cma.port"));      
		cmd.add("-a");
		cmd.add(jobConf.get("mapred.netmerger.merge.approach"));
		cmd.add("-m");
		cmd.add("1");
		
		cmd.add("-g");
		cmd.add(jobConf.get("mapred.rdma.log.dir","default") + logdirTail);
		
		cmd.add("-b");
		cmd.add(jobConf.get("mapred.netmerger.rdma.num.buffers"));
		cmd.add("-s");
		cmd.add(jobConf.get("mapred.rdma.buf.size"));
		cmd.add("-t");
		cmd.add(jobConf.get("mapred.uda.log.tracelevel"));

		LOG.info("going to execute C++ thru JNI with argc=: " + cmd.size() + " cmd: " + cmd);    	  
		String[] stringarray = cmd.toArray(new String[0]);

		try {
			UdaBridge.start(isNetMerger, stringarray, LOG, _callable);

		} catch (UnsatisfiedLinkError e) {
			LOG.warn("UDA: Exception when launching child");    	  
			LOG.warn("java.library.path=" + System.getProperty("java.library.path"));
			LOG.warn(StringUtils.stringifyException(e));
			throw (e);
		}
	}

}

class UdaPluginRT<K,V> extends UdaPlugin implements UdaCallable {

	final ReduceCopier reduceCopier;
	final ReduceTask reduceTask;

	private TaskReporter      mTaskReporter = null;    
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

	private void init_kv_bufs() {
		kv_bufs = new KVBuf[kv_buf_num];
		for (int idx = 0; idx < kv_buf_num; ++idx) {
			kv_bufs[idx] = new KVBuf(kv_buf_size);
		} 
	}

	public UdaPluginRT(ReduceCopier reduceCopier, ReduceTask reduceTask, JobConf jobConf, TaskReporter reporter,
			int numMaps) throws IOException {
		this.reduceTask = reduceTask;
		this.reduceCopier = reduceCopier;

		/* init variables */
		init_kv_bufs(); 

		launchCppSide(true, jobConf, this, "/userlogs/" + reduceTask.getTaskID().getJobID().toString() + "/"  + reduceTask.getTaskID().toString() ); // true: this is RT => we should execute NetMerger

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

		LOG.info("UDA: sending INIT_COMMAND");    	  
		String msg = RDMACmd.formCmd(RDMACmd.INIT_COMMAND, mParams);
		UdaBridge.doCommand(msg);
		this.mProgress = new Progress(); 
		this.mProgress.set((float)(1/2));
	}

	public void sendFetchReq (MapOutputLocation loc) {
		/* "host:jobid:mapid:reduce" */
		mParams.clear();
		mParams.add(loc.getHost());
		mParams.add(loc.getTaskAttemptId().getJobID().toString());
		mParams.add(loc.getTaskAttemptId().toString());
		mParams.add(Integer.toString(reduceTask.getPartition()));
		String msg = RDMACmd.formCmd(RDMACmd.FETCH_COMMAND, mParams); 
		UdaBridge.doCommand(msg);
	}

	public void close() {
		mParams.clear();
		LOG.info("UDA: sending EXIT_COMMAND");    	  
		String msg = RDMACmd.formCmd(RDMACmd.EXIT_COMMAND, mParams);
		UdaBridge.doCommand(msg);
		this.j2c_queue.close();
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
			/* wake up ReduceCopier */
			if (LOG.isInfoEnabled()) LOG.info("fetchOverMessage: reached desired num of maps, waking up ReduceCopier"); 
			synchronized(reduceCopier) {
				reduceCopier.notify();
			}
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
				synchronized (buf) {
					buf.notifyAll();
				}
			}
		}

		public Progress getProgress() {
			return mProgress;
		}

	}
}



//*  The following is for MOFSupplier JavaSide. 
class UdaPluginTT extends UdaPlugin {    

	private final TaskTracker taskTracker;
	private Vector<String>     mParams       = new Vector<String>();

	public UdaPluginTT(TaskTracker taskTracker) {
		this.taskTracker = taskTracker;
		
		launchCppSide(false, this.taskTracker.fConf, null, ""); // false: this is TT => we should execute MOFSupplier
	}

	public void jobOver(String jobId) {
		mParams.clear();
		mParams.add(jobId);
		String msg = RDMACmd.formCmd(RDMACmd.JOB_OVER_COMMAND, mParams);
		LOG.info("UDA: sending JOBOVER:(" + msg + ")");
		UdaBridge.doCommand(msg);
	}  

	public void notifyMapDone(String userName, String jobId, String mapId) {
		try {
			//parent path for the file.out file
			Path fout = this.taskTracker.localDirAllocator.getLocalPathToRead(
					TaskTracker.getIntermediateOutputDir(userName, jobId, mapId) 
					+ "/file.out", this.taskTracker.fConf);

			//parent path for the file.out.index file
			Path fidx = this.taskTracker.localDirAllocator.getLocalPathToRead(
					TaskTracker.getIntermediateOutputDir(userName, jobId, mapId) 
					+ "/file.out.index", this.taskTracker.fConf);

			int upper = 6;
			for (int i = 0; i < upper; ++i) {
				fout = fout.getParent();
				fidx = fidx.getParent();
			} 

			//we need "jobId + mapId" to identify a maptask
			mParams.clear();
			mParams.add(jobId);
			mParams.add(mapId);
			mParams.add(fout.toString()); 
			mParams.add(fidx.toString());
			mParams.add(userName);
			String msg = RDMACmd.formCmd(RDMACmd.NEW_MAP_COMMAND, mParams);
			UdaBridge.doCommand(msg);

			if (LOG.isInfoEnabled()) LOG.info("UDA: notified Finshed Map:(" + msg + ")");

		} catch (DiskChecker.DiskErrorException dee) {
			LOG.info("UDA: DiskErrorException when handling map done - probably OK (map was not created)\n" + StringUtils.stringifyException(dee));
		} catch (IOException ioe) {
			LOG.error("UDA: Error when notify map done\n" + StringUtils.stringifyException(ioe));
		}
	}

	public void close() {

		mParams.clear();
		String msg = RDMACmd.formCmd(RDMACmd.EXIT_COMMAND, mParams);
		LOG.info("UDA: sending EXIT_COMMAND");    	  
		UdaBridge.doCommand(msg);        
	}
}
