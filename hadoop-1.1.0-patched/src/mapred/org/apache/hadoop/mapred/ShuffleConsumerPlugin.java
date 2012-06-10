/**
 * 
 */
package org.apache.hadoop.mapred;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
import java.net.URLClassLoader;
import java.util.ArrayList;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;



import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.IntWritable;
import org.apache.hadoop.mapred.JobConf;
import org.apache.hadoop.mapred.Task;
import org.apache.hadoop.mapred.Task.TaskReporter;
import org.apache.hadoop.mapred.TaskTracker;
import org.apache.hadoop.util.ReflectionUtils;
import org.apache.hadoop.util.StringUtils;


/**
 * Plugin to serve Reducers who request MapOutput from TaskTrackers that use a matching ShuffleProvidePlugin
 * 
 */
public abstract class ShuffleConsumerPlugin {
	
	  /**
	   * Factory method for getting the ShuffleConsumerPlugin from the given class object and configure it. 
	   * If clazz is null, this method will return a the builtin ShuffleConsumerPlugin
	   * 
	   * @param clazz class
	   * @param conf configure the plugin with this.
	   * @return ShuffleConsumerPlugin
	   */
	public static ShuffleConsumerPlugin getShuffleConsumerPlugin(Class<? extends ShuffleConsumerPlugin> clazz, Configuration conf) {
	    if (clazz != null) {
	        return ReflectionUtils.newInstance(clazz, conf);
	      }
	    else {
	    	return new ReduceCopier(); // builtin plugin
	    }
	}

	private static final Log LOG = LogFactory.getLog(ShuffleConsumerPlugin.class.getName());

	/** Reference to the umbilical object */
	protected TaskUmbilicalProtocol umbilical;

	protected TaskReporter reporter;

	protected ReduceTask reduceTask;
	protected JobConf jobConf;
	
	
	/**
	 * Number of files to merge at a time
	 */
	protected int ioSortFactor;
	
	/**
	 * A reference to the throwable object (if merge throws an exception)
	 */
	protected volatile Throwable mergeThrowable;


	/**
	 * When we accumulate maxInMemOutputs number of files in ram, we merge/spill
	 */
	protected int maxInMemOutputs;

	/**
	 * Usage threshold for in-memory output accumulation.
	 */
	protected float maxInMemCopyPer;

	/**
	 * Maximum memory usage of map outputs to merge from memory into
	 * the reduce, in bytes.
	 */
	protected long maxInMemReduce;

    protected int numEventsFetched = 0;
    protected Object copyResultsOrNewEventsLock = new Object();


	/**
	 *  the number of outputs to copy in parallel
	 */
	protected int numCopiers;

	/**
	 * Default limit for maximum number of fetch failures before reporting.
	 */
	protected final static int REPORT_FAILURE_LIMIT = 10;

	/**
	 * Maximum number of fetch-retries per-map before reporting it.
	 */
	protected int maxFetchFailuresBeforeReporting;

	/** 
	 * A flag to indicate when to exit getMapEvents thread 
	 */
	protected volatile boolean exitGetMapEvents = false;

	protected boolean reportReadErrorImmediately;

	protected TaskAttemptID reduceId;

	
	
	/**
	 * initialize this ShuffleConsumer instance.  The base class implementation will initialize its members and 
	 * then invoke initPlugin for plugin specific initiaiztion
	 * 
	 * @param reduceTask
	 * @param umbilical
	 * @param jobConf
	 * @param reporter
	 * @throws ClassNotFoundException
	 * @throws IOException
	 */
	protected void init(ReduceTask reduceTask, TaskUmbilicalProtocol umbilical, JobConf jobConf, TaskReporter reporter) throws ClassNotFoundException, IOException {
		this.reduceTask = reduceTask;
		this.reduceId = reduceTask.getTaskID();

		this.umbilical = umbilical;
		this.jobConf = jobConf;
		this.reporter = reporter;

		configureClasspath(jobConf);

		this.numCopiers = jobConf.getInt("mapred.reduce.parallel.copies", 5);
		this.ioSortFactor = jobConf.getInt("io.sort.factor", 10);
		this.maxFetchFailuresBeforeReporting = jobConf.getInt(
				"mapreduce.reduce.shuffle.maxfetchfailures", REPORT_FAILURE_LIMIT);


		this.maxInMemOutputs = jobConf.getInt("mapred.inmem.merge.threshold", 1000);
		this.maxInMemCopyPer =
				jobConf.getFloat("mapred.job.shuffle.merge.percent", 0.66f);
		final float maxRedPer =
				jobConf.getFloat("mapred.job.reduce.input.buffer.percent", 0f);
		if (maxRedPer > 1.0 || maxRedPer < 0.0) {
			throw new IOException("mapred.job.reduce.input.buffer.percent" +
					maxRedPer);
		}
		this.maxInMemReduce = (int)Math.min(
				Runtime.getRuntime().maxMemory() * maxRedPer, Integer.MAX_VALUE);
		
		this.reportReadErrorImmediately = 
				jobConf.getBoolean("mapreduce.reduce.shuffle.notify.readerror", true);
	
		// Do any plugin specific initialization here
		initPlugin();
	}

	/**
	 * performs plugin specific initialization
	 * 
	 * @throws ClassNotFoundException
	 * @throws IOException
	 */
	abstract protected void initPlugin() throws ClassNotFoundException, IOException;
	
	
	/**
	 * fetch output of mappers from TaskTrackers
	 * @return true iff success
	 * @throws IOException
	 */
	protected abstract boolean fetchOutputs() throws IOException;

	/**
	 * starts this ShuffleConsumer.  the base class implementation will invoke init & fetchOutputs 
	 * @param reduceTask
	 * @param umbilical
	 * @param jobConf
	 * @param reporter
	 * @return true iff success
	 * @throws ClassNotFoundException
	 * @throws IOException
	 */
	public boolean start(ReduceTask reduceTask, TaskUmbilicalProtocol umbilical, JobConf jobConf, TaskReporter reporter) throws ClassNotFoundException, IOException {

		init(reduceTask, umbilical, jobConf, reporter);
		return fetchOutputs();
	}

	
	/**
	 * called from  GetMapEventsThread.getMapCompletionEvents() upon map completion event 
	 * 
	 * @param event
	 * @throws Exception
	 */
	abstract public void mapCompleted(TaskCompletionEvent event) throws Exception;

	/**
	 * 
	 * called from  GetMapEventsThread.getMapCompletionEvents() upon notification from JobTracker 
	 * This may be needed for syncing with jobtracker for job that was recovered
	 * 
	 */
	abstract public void resetKnownMaps();


	// SORT phase:
	/**
	 * Create a RawKeyValueIterator from copied map outputs. 
	 * 
	 * The iterator returned must satisfy the following constraints:
	 *   1. Fewer than io.sort.factor files may be sources
	 *   2. No more than maxInMemReduce bytes of map outputs may be resident
	 *      in memory when the reduce begins
	 *
	 * If we must perform an intermediate merge to satisfy (1), then we can
	 * keep the excluded outputs from (2) in memory and include them in the
	 * first merge pass. If not, then said outputs must be written to disk
	 * first.
	 */
	public abstract RawKeyValueIterator createKVIterator(JobConf job, FileSystem fs, Reporter reporter) throws IOException;

	// after REDUCE phase:
	public abstract void close();

	
	protected void configureClasspath(JobConf conf)
			throws IOException {

		// get the task and the current classloader which will become the parent
		Task task = reduceTask;
		ClassLoader parent = conf.getClassLoader();   

		// get the work directory which holds the elements we are dynamically
		// adding to the classpath
		File workDir = new File(task.getJobFile()).getParentFile();
		ArrayList<URL> urllist = new ArrayList<URL>();

		// add the jars and directories to the classpath
		String jar = conf.getJar();
		if (jar != null) {      
			File jobCacheDir = new File(new Path(jar).getParent().toString());

			File[] libs = new File(jobCacheDir, "lib").listFiles();
			if (libs != null) {
				for (int i = 0; i < libs.length; i++) {
					urllist.add(libs[i].toURL());
				}
			}
			urllist.add(new File(jobCacheDir, "classes").toURL());
			urllist.add(jobCacheDir.toURL());

		}
		urllist.add(workDir.toURL());

		// create a new classloader with the old classloader as its parent
		// then set that classloader as the one used by the current jobconf
		URL[] urls = urllist.toArray(new URL[urllist.size()]);
		URLClassLoader loader = new URLClassLoader(urls, parent);
		conf.setClassLoader(loader);
	}



	///////////////////////////////////////////////////////////////
	/////////                                  ////////////////////
	/////////  INNER CLASSES - for plugins use ////////////////////
	/////////                                  ////////////////////
	///////////////////////////////////////////////////////////////


	/**
	 * Abstraction to track a map-output.
	 */
	protected class MapOutputLocation {
		TaskAttemptID taskAttemptId;
		TaskID taskId;
		String ttHost;
		URL taskOutput;

		public MapOutputLocation(TaskAttemptID taskAttemptId, 
				String ttHost, URL taskOutput) {
			this.taskAttemptId = taskAttemptId;
			this.taskId = this.taskAttemptId.getTaskID();
			this.ttHost = ttHost;
			this.taskOutput = taskOutput;
		}

		public TaskAttemptID getTaskAttemptId() {
			return taskAttemptId;
		}

		public TaskID getTaskId() {
			return taskId;
		}

		public String getHost() {
			return ttHost;
		}

		public URL getOutputLocation() {
			return taskOutput;
		}
	}

	/** Describes the output of a map; could either be on disk or in-memory. */
	protected class MapOutput {
		final TaskID mapId;
		final TaskAttemptID mapAttemptId;

		final Path file;
		final Configuration conf;

		byte[] data;
		final boolean inMemory;
		long compressedSize;

		public MapOutput(TaskID mapId, TaskAttemptID mapAttemptId, 
				Configuration conf, Path file, long size) {
			this.mapId = mapId;
			this.mapAttemptId = mapAttemptId;

			this.conf = conf;
			this.file = file;
			this.compressedSize = size;

			this.data = null;

			this.inMemory = false;
		}

		public MapOutput(TaskID mapId, TaskAttemptID mapAttemptId, byte[] data, int compressedLength) {
			this.mapId = mapId;
			this.mapAttemptId = mapAttemptId;

			this.file = null;
			this.conf = null;

			this.data = data;
			this.compressedSize = compressedLength;

			this.inMemory = true;
		}

		public void discard() throws IOException {
			if (inMemory) {
				data = null;
			} else {
				FileSystem fs = file.getFileSystem(conf);
				fs.delete(file, true);
			}
		}
	}

	class ShuffleRamManager implements RamManager {
		/* Maximum percentage of the in-memory limit that a single shuffle can 
		 * consume*/ 
		private static final float MAX_SINGLE_SHUFFLE_SEGMENT_FRACTION = 0.25f;

		/* Maximum percentage of shuffle-threads which can be stalled 
		 * simultaneously after which a merge is triggered. */ 
		private static final float MAX_STALLED_SHUFFLE_THREADS_FRACTION = 0.75f;

		private final long maxSize;
		private final long maxSingleShuffleLimit;

		private long size = 0;

		private Object dataAvailable = new Object();
		private long fullSize = 0;
		private int numPendingRequests = 0;
		private int numRequiredMapOutputs = 0;
		private int numClosed = 0;
		private boolean closed = false;

		public ShuffleRamManager(Configuration conf) throws IOException {
			final float maxInMemCopyUse =
					conf.getFloat("mapred.job.shuffle.input.buffer.percent", 0.70f);
			if (maxInMemCopyUse > 1.0 || maxInMemCopyUse < 0.0) {
				throw new IOException("mapred.job.shuffle.input.buffer.percent" +
						maxInMemCopyUse);
			}
			// Allow unit tests to fix Runtime memory
			maxSize = (int)(conf.getInt("mapred.job.reduce.total.mem.bytes",
					(int)Math.min(Runtime.getRuntime().maxMemory(), Integer.MAX_VALUE))
					* maxInMemCopyUse);
			maxSingleShuffleLimit = (long)(maxSize * MAX_SINGLE_SHUFFLE_SEGMENT_FRACTION);
			LOG.info("ShuffleRamManager: MemoryLimit=" + maxSize + 
					", MaxSingleShuffleLimit=" + maxSingleShuffleLimit);
		}

		public synchronized boolean reserve(int requestedSize, InputStream in) 
				throws InterruptedException {
			// Wait till the request can be fulfilled...
			while ((size + requestedSize) > maxSize) {

				// Close the input...
				if (in != null) {
					try {
						in.close();
					} catch (IOException ie) {
						LOG.info("Failed to close connection with: " + ie);
					} finally {
						in = null;
					}
				} 

				// Track pending requests
				synchronized (dataAvailable) {
					++numPendingRequests;
					dataAvailable.notify();
				}

				// Wait for memory to free up
				wait();

				// Track pending requests
				synchronized (dataAvailable) {
					--numPendingRequests;
				}
			}

			size += requestedSize;

			return (in != null);
		}

		public synchronized void unreserve(int requestedSize) {
			size -= requestedSize;

			synchronized (dataAvailable) {
				fullSize -= requestedSize;
				--numClosed;
			}

			// Notify the threads blocked on RamManager.reserve
			notifyAll();
		}

		public boolean waitForDataToMerge() throws InterruptedException {
			boolean done = false;
			synchronized (dataAvailable) {
				// Start in-memory merge if manager has been closed or...
				while (!closed
						&&
						// In-memory threshold exceeded and at least two segments
						// have been fetched
						(getPercentUsed() < maxInMemCopyPer || numClosed < 2)
						&&
						// More than "mapred.inmem.merge.threshold" map outputs
						// have been fetched into memory
						(maxInMemOutputs <= 0 || numClosed < maxInMemOutputs)
						&& 
						// More than MAX... threads are blocked on the RamManager
						// or the blocked threads are the last map outputs to be
						// fetched. If numRequiredMapOutputs is zero, either
						// setNumCopiedMapOutputs has not been called (no map ouputs
						// have been fetched, so there is nothing to merge) or the
						// last map outputs being transferred without
						// contention, so a merge would be premature.
						(numPendingRequests < 
								numCopiers*MAX_STALLED_SHUFFLE_THREADS_FRACTION && 
								(0 == numRequiredMapOutputs ||
								numPendingRequests < numRequiredMapOutputs))) {
					dataAvailable.wait();
				}
				done = closed;
			}
			return done;
		}

		public void closeInMemoryFile(int requestedSize) {
			synchronized (dataAvailable) {
				fullSize += requestedSize;
				++numClosed;
				dataAvailable.notify();
			}
		}

		public void setNumCopiedMapOutputs(int numRequiredMapOutputs) {
			synchronized (dataAvailable) {
				this.numRequiredMapOutputs = numRequiredMapOutputs;
				dataAvailable.notify();
			}
		}

		public void close() {
			synchronized (dataAvailable) {
				closed = true;
				LOG.info("Closed ram manager");
				dataAvailable.notify();
			}
		}

		private float getPercentUsed() {
			return (float)fullSize/maxSize;
		}

		boolean canFitInMemory(long requestedSize) {
			return (requestedSize < Integer.MAX_VALUE && 
					requestedSize < maxSingleShuffleLimit);
		}
	}


	/* 
	This class was moved to here instead of being inner class of ReduceCopier 
	In addition took out some code from getMapCompletionEvents() method and put it in ReduceCopier
	The code in ReduceCopier will be executed by notifying ShuffleConsumerPlugin of the following events:
	- mapCompleted(event);
	- resetKnownMaps()	
	 */
	protected class GetMapEventsThread extends Thread {

		/** Max events to fetch in one go from the tasktracker */
		private static final int MAX_EVENTS_TO_FETCH = 10000;


		private IntWritable fromEventId = new IntWritable(0);
		private static final long SLEEP_TIME = 1000;

		public GetMapEventsThread() {
			setName("Thread for polling Map Completion Events");
			setDaemon(true);
		}

		@Override
		public void run() {

			LOG.info(reduceId + " Thread started: " + getName());

			do {
				try {
					int numNewMaps = getMapCompletionEvents();
				        if (numNewMaps > 0) {
				           synchronized (copyResultsOrNewEventsLock) {
				              numEventsFetched += numNewMaps;
				              copyResultsOrNewEventsLock.notifyAll();
				           }
				         }
					if (LOG.isDebugEnabled()) {
						if (numNewMaps > 0) {
							LOG.debug(reduceId + ": " +  
									"Got " + numNewMaps + " new map-outputs"); 
						}
					}
					Thread.sleep(SLEEP_TIME);
				} 
				catch (InterruptedException e) {
					LOG.warn(reduceId +
							" GetMapEventsThread returning after an " +
							" interrupted exception");
					return;
				}
				catch (Throwable t) {
					String msg = reduceId
							+ " GetMapEventsThread Ignoring exception : " 
							+ StringUtils.stringifyException(t);

					reduceTask.reportFatalError(reduceId, t, msg);
				}
			} while (!exitGetMapEvents);

			LOG.info("GetMapEventsThread exiting");

		}

		/** 
		 * Queries the {@link TaskTracker} for a set of map-completion events 
		 * from a given event ID.
		 * @throws IOException
		 */  
		private int getMapCompletionEvents() throws Exception {

			int numNewMaps = 0;

			MapTaskCompletionEventsUpdate update = 
					umbilical.getMapCompletionEvents(reduceTask.getJobID(),
							fromEventId.get(), 
							MAX_EVENTS_TO_FETCH,
							reduceId, reduceTask.jvmContext);
			TaskCompletionEvent events[] = update.getMapTaskCompletionEvents();

			// Check if the reset is required.
			// Since there is no ordering of the task completion events at the 
			// reducer, the only option to sync with the new jobtracker is to reset 
			// the events index
			if (update.shouldReset()) {
				fromEventId.set(0);
				resetKnownMaps(); // notify ShuffleConsumerPlugin
			}

			// Update the last seen event ID
			fromEventId.set(fromEventId.get() + events.length);

			// Process the TaskCompletionEvents (using ShuffleConsumerPlugin handler function):
			for (TaskCompletionEvent event : events) {
				mapCompleted(event);    // notify ShuffleConsumerPlugin
				if (event.getTaskStatus() == TaskCompletionEvent.Status.SUCCEEDED) ++numNewMaps; 
			}
			return numNewMaps;
		}
	}


}
