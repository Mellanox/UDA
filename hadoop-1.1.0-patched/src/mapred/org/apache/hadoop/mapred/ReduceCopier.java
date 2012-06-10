/**
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.apache.hadoop.mapred;


import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URL;
import java.net.URLClassLoader;
import java.net.URLConnection;
import java.text.DecimalFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.Iterator;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.Set;
import java.util.TreeSet;
import java.util.concurrent.ConcurrentHashMap;

import javax.crypto.SecretKey;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.ChecksumFileSystem;
import org.apache.hadoop.fs.FSError;
import org.apache.hadoop.fs.FileStatus;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.LocalFileSystem;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.DataInputBuffer;
import org.apache.hadoop.io.IOUtils;
import org.apache.hadoop.io.IntWritable;
import org.apache.hadoop.io.RawComparator;
import org.apache.hadoop.io.WritableUtils;
import org.apache.hadoop.io.compress.CodecPool;
import org.apache.hadoop.io.compress.CompressionCodec;
import org.apache.hadoop.io.compress.Decompressor;
import org.apache.hadoop.io.compress.DefaultCodec;
import org.apache.hadoop.mapred.Counters;
import org.apache.hadoop.mapred.IFile.Reader;
import org.apache.hadoop.mapred.IFile.Writer;
import org.apache.hadoop.mapred.IFile.InMemoryReader;
import org.apache.hadoop.mapred.MapTaskCompletionEventsUpdate;
import org.apache.hadoop.mapred.Merger.Segment;
import org.apache.hadoop.mapred.RawKeyValueIterator;
import org.apache.hadoop.mapred.Reporter;
import org.apache.hadoop.mapred.Task.CombineOutputCollector;
import org.apache.hadoop.mapred.Task.CombinerRunner;
import org.apache.hadoop.mapred.Task.TaskReporter;
import org.apache.hadoop.mapreduce.security.SecureShuffleUtils;
import org.apache.hadoop.metrics2.MetricsBuilder;
import org.apache.hadoop.metrics2.MetricsRecordBuilder;
import org.apache.hadoop.metrics2.MetricsSource;
import org.apache.hadoop.metrics2.lib.DefaultMetricsSystem;
import org.apache.hadoop.metrics2.lib.MetricMutableCounterInt;
import org.apache.hadoop.metrics2.lib.MetricMutableCounterLong;
import org.apache.hadoop.metrics2.lib.MetricsRegistry;
import org.apache.hadoop.util.Progress;
import org.apache.hadoop.util.ReflectionUtils;
import org.apache.hadoop.util.StringUtils;

import org.apache.hadoop.mapred.ShuffleConsumerPlugin.MapOutputLocation;

import org.apache.hadoop.fs.LocalDirAllocator;

class ReduceCopier<K, V> extends ShuffleConsumerPlugin implements MRConstants{
	
	protected void initPlugin() throws ClassNotFoundException, IOException {

		this.shuffleClientMetrics = createShuffleClientInstrumentation();

		this.scheduledCopies = new ArrayList<MapOutputLocation>(100);
		this.copyResults = new ArrayList<CopyResult>(100);    
		this.maxInFlight = 4 * numCopiers;
		Counters.Counter combineInputCounter = 
				reporter.getCounter(Task.Counter.COMBINE_INPUT_RECORDS);
		this.combinerRunner = CombinerRunner.create(jobConf, reduceId,
				combineInputCounter,
				reporter, null);
		if (combinerRunner != null) {
			combineCollector = 
					new CombineOutputCollector(reduceTask.reduceCombineOutputCounter, reporter, jobConf);
		}

		this.abortFailureLimit = Math.max(30, reduceTask.getNumMaps() / 10);

		this.maxFailedUniqueFetches = Math.min(reduceTask.getNumMaps(), 
				this.maxFailedUniqueFetches);

		// Setup the RamManager
		ramManager = new ShuffleRamManager(jobConf);

		localFileSys = FileSystem.getLocal(jobConf);

		rfs = ((LocalFileSystem)localFileSys).getRaw();

		// hosts -> next contact time
		this.penaltyBox = new LinkedHashMap<String, Long>();

		// hostnames
		this.uniqueHosts = new HashSet<String>();

		// Seed the random number generator with a reasonably globally unique seed
		long randomSeed = System.nanoTime() + 
				(long)Math.pow(this.reduceTask.getPartition(),
						(this.reduceTask.getPartition()%10)
						);
		this.random = new Random(randomSeed);
		this.maxMapRuntime = 0;

	}

	/**
	 * 
	 * TaskTracker notified us that a reset is required
	 * This may be needed for syncing with jobtracker for job that was recovered
	 * 
	 */
	public void resetKnownMaps() {
		obsoleteMapIds.clear(); // clear the obsolete map 
		mapLocations.clear(); // clear the map locations mapping		
	}


	// Process the TaskCompletionEvent:
	// 1. Save the SUCCEEDED maps in knownOutputs to fetch the outputs.
	// 2. Save the OBSOLETE/FAILED/KILLED maps in obsoleteOutputs to stop 
	//    fetching from those maps.
	// 3. Remove TIPFAILED maps from neededOutputs since we don't need their
	//    outputs at all.
	public void mapCompleted(TaskCompletionEvent event) throws IOException {
		switch (event.getTaskStatus()) {
		case SUCCEEDED:
		{
			URI u = URI.create(event.getTaskTrackerHttp());
			String host = u.getHost();
			TaskAttemptID taskId = event.getTaskAttemptId();
			URL mapOutputUrl = new URL(event.getTaskTrackerHttp() + 
					"/mapOutput?job=" + taskId.getJobID() +
					"&map=" + taskId + 
					"&reduce=" + reduceTask.getPartition());

			MapOutputLocation mapOutputLocation = new MapOutputLocation(taskId, host, mapOutputUrl); 

			List<MapOutputLocation> loc = mapLocations.get(host);
			if (loc == null) {
				loc = Collections.synchronizedList (new LinkedList<MapOutputLocation>());
				mapLocations.put(host, loc);
			}
			loc.add(mapOutputLocation);

		}
		break;
		case FAILED:
		case KILLED:
		case OBSOLETE:
		{
			obsoleteMapIds.add(event.getTaskAttemptId());
			LOG.info("Ignoring obsolete output of " + event.getTaskStatus() + 
					" map-task: '" + event.getTaskAttemptId() + "'");
		}
		break;
		case TIPFAILED:
		{
			copiedMapOutputs.add(event.getTaskAttemptId().getTaskID());
			LOG.info("Ignoring output of failed map TIP: '" +  
					event.getTaskAttemptId() + "'");
		}
		break;
		}

	}


	public void close() {
	}




	private static final Log LOG = LogFactory.getLog(ReduceCopier.class.getName());

	private static enum CopyOutputErrorType {
		NO_ERROR,
		READ_ERROR,
		OTHER_ERROR
	};




	/** Number of ms before timing out a copy */
	private static final int STALLED_COPY_TIMEOUT = 3 * 60 * 1000;

    /**
     * the list of map outputs currently being copied
     */
    private List<MapOutputLocation> scheduledCopies;
    
    /**
     *  the results of dispatched copy attempts
     */
    private List<CopyResult> copyResults;
    
    
    /**
     *  a number that is set to the max #fetches we'd schedule and then
     *  pause the schduling
     */
    private int maxInFlight;
    
    
    /**
     * busy hosts from which copies are being backed off
     * Map of host -> next contact time
     */
    private Map<String, Long> penaltyBox;
    
    /**
     * the set of unique hosts from which we are copying
     */
    private Set<String> uniqueHosts;
    
    /**
     * A reference to the RamManager for writing the map outputs to.
     */
    
    private ShuffleRamManager ramManager;
    
    /**
     * A reference to the local file system for writing the map outputs to.
     */
    private FileSystem localFileSys;

    private FileSystem rfs;
    
    /** 
     * A flag to indicate when to exit localFS merge
     */
    private volatile boolean exitLocalFSMerge = false;

    /** 
     * The threads for fetching the files.
     */
    private List<MapOutputCopier> copiers = null;
    
    /**
     * The object for metrics reporting.
     */
    private ShuffleClientInstrumentation shuffleClientMetrics;
    
    /**
     * the minimum interval between tasktracker polls
     */
    private static final long MIN_POLL_INTERVAL = 1000;
    
    /**
     * a list of map output locations for fetch retrials 
     */
    private List<MapOutputLocation> retryFetches =
      new ArrayList<MapOutputLocation>();
    
    /** 
     * The set of required map outputs
     */
    private Set <TaskID> copiedMapOutputs = 
      Collections.synchronizedSet(new TreeSet<TaskID>());
    
    /** 
     * The set of obsolete map taskids.
     */
    private Set <TaskAttemptID> obsoleteMapIds = 
      Collections.synchronizedSet(new TreeSet<TaskAttemptID>());
    
    private Random random = null;

    /**
     * the max of all the map completion times
     */
    private int maxMapRuntime;
    
    /**
     * Maximum number of fetch failures before reducer aborts.
     */
	private int abortFailureLimit;

    /**
     * Initial penalty time in ms for a fetch failure.
     */
    private static final long INITIAL_PENALTY = 10000;

    /**
     * Penalty growth rate for each fetch failure.
     */
    private static final float PENALTY_GROWTH_RATE = 1.3f;

    /**
     * Combiner runner, if a combiner is needed
     */
    private CombinerRunner combinerRunner;

    /**
     * Resettable collector used for combine.
     */
    private CombineOutputCollector combineCollector = null;

    /**
     * Maximum percent of failed fetch attempt before killing the reduce task.
     */
    private static final float MAX_ALLOWED_FAILED_FETCH_ATTEMPT_PERCENT = 0.5f;

    /**
     * Minimum percent of progress required to keep the reduce alive.
     */
    private static final float MIN_REQUIRED_PROGRESS_PERCENT = 0.5f;

    /**
     * Maximum percent of shuffle execution time required to keep the reducer alive.
     */
    private static final float MAX_ALLOWED_STALL_TIME_PERCENT = 0.5f;
    
    /**
     * Minimum number of map fetch retries.
     */
    private static final int MIN_FETCH_RETRIES_PER_MAP = 2;

    /**
     * The minimum percentage of maps yet to be copied, 
     * which indicates end of shuffle
     */
    private static final float MIN_PENDING_MAPS_PERCENT = 0.25f;
    /**
     * Maximum no. of unique maps from which we failed to fetch map-outputs
     * even after {@link #maxFetchRetriesPerMap} retries; after this the
     * reduce task is failed.
     */
    private int maxFailedUniqueFetches = 5;

    /**
     * The maps from which we fail to fetch map-outputs 
     * even after {@link #maxFetchRetriesPerMap} retries.
     */
    Set<TaskID> fetchFailedMaps = new TreeSet<TaskID>(); 
    
    /**
     * A map of taskId -> no. of failed fetches
     */
    Map<TaskAttemptID, Integer> mapTaskToFailedFetchesMap = 
      new HashMap<TaskAttemptID, Integer>();    

    /**
     * Initial backoff interval (milliseconds)
     */
    private static final int BACKOFF_INIT = 4000; 
    
    /**
     * The interval for logging in the shuffle
     */
    private static final int MIN_LOG_TIME = 60000;

    /** 
     * List of in-memory map-outputs.
     */
    private final List<MapOutput> mapOutputsFilesInMemory =
      Collections.synchronizedList(new LinkedList<MapOutput>());
    
    /**
     * The map for (Hosts, List of MapIds from this Host) maintaining
     * map output locations
     */
    private final Map<String, List<MapOutputLocation>> mapLocations = 
      new ConcurrentHashMap<String, List<MapOutputLocation>>();

    class ShuffleClientInstrumentation implements MetricsSource {
      final MetricsRegistry registry = new MetricsRegistry("shuffleInput");
      final MetricMutableCounterLong inputBytes =
          registry.newCounter("shuffle_input_bytes", "", 0L);
      final MetricMutableCounterInt failedFetches =
          registry.newCounter("shuffle_failed_fetches", "", 0);
      final MetricMutableCounterInt successFetches =
          registry.newCounter("shuffle_success_fetches", "", 0);
      private volatile int threadsBusy = 0;

      @SuppressWarnings("deprecation")
      ShuffleClientInstrumentation(JobConf conf) {
        registry.tag("user", "User name", conf.getUser())
                .tag("jobName", "Job name", conf.getJobName())
			.tag("jobId", "Job ID", reduceTask.getJobID().toString())
			.tag("taskId", "Task ID", reduceId.toString())
                .tag("sessionId", "Session ID", conf.getSessionId());
      }

      //@Override
      void inputBytes(long numBytes) {
        inputBytes.incr(numBytes);
      }

      //@Override
      void failedFetch() {
        failedFetches.incr();
      }

      //@Override
      void successFetch() {
        successFetches.incr();
      }

      //@Override
      synchronized void threadBusy() {
        ++threadsBusy;
      }

      //@Override
      synchronized void threadFree() {
        --threadsBusy;
      }

      @Override
      public void getMetrics(MetricsBuilder builder, boolean all) {
        MetricsRecordBuilder rb = builder.addRecord(registry.name());
        rb.addGauge("shuffle_fetchers_busy_percent", "", numCopiers == 0 ? 0
            : 100. * threadsBusy / numCopiers);
        registry.snapshot(rb, all);
      }

    }

    private ShuffleClientInstrumentation createShuffleClientInstrumentation() {
      return DefaultMetricsSystem.INSTANCE.register("ShuffleClientMetrics",
				"Shuffle input metrics", new ShuffleClientInstrumentation(reduceTask.conf));
    }

    /** Represents the result of an attempt to copy a map output */
    private class CopyResult {
      
      // the map output location against which a copy attempt was made
      private final MapOutputLocation loc;
      
      // the size of the file copied, -1 if the transfer failed
      private final long size;
      
      //a flag signifying whether a copy result is obsolete
      private static final int OBSOLETE = -2;
      
      private CopyOutputErrorType error = CopyOutputErrorType.NO_ERROR;
      CopyResult(MapOutputLocation loc, long size) {
        this.loc = loc;
        this.size = size;
      }

      CopyResult(MapOutputLocation loc, long size, CopyOutputErrorType error) {
        this.loc = loc;
        this.size = size;
        this.error = error;
      }

      public boolean getSuccess() { return size >= 0; }
      public boolean isObsolete() { 
        return size == OBSOLETE;
      }
      public long getSize() { return size; }
      public String getHost() { return loc.getHost(); }
      public MapOutputLocation getLocation() { return loc; }
      public CopyOutputErrorType getError() { return error; }
    }
    
    private int nextMapOutputCopierId = 0;

    /** Copies map outputs as they become available */
    private class MapOutputCopier extends Thread {
      // basic/unit connection timeout (in milliseconds)
      private final static int UNIT_CONNECT_TIMEOUT = 30 * 1000;
      // default read timeout (in milliseconds)
      private final static int DEFAULT_READ_TIMEOUT = 3 * 60 * 1000;
      private final int shuffleConnectionTimeout;
      private final int shuffleReadTimeout;

      private MapOutputLocation currentLocation = null;
      private int id = nextMapOutputCopierId++;
      private Reporter reporter;
      private boolean readError = false;
      
      // Decompression of map-outputs
      private CompressionCodec codec = null;
      private Decompressor decompressor = null;
      
      private final SecretKey jobTokenSecret;
      
      public MapOutputCopier(JobConf job, Reporter reporter, SecretKey jobTokenSecret) {
			setName("MapOutputCopier " + reduceId + "." + id);
        LOG.debug(getName() + " created");
        this.reporter = reporter;

        this.jobTokenSecret = jobTokenSecret;
 
        shuffleConnectionTimeout =
          job.getInt("mapreduce.reduce.shuffle.connect.timeout", STALLED_COPY_TIMEOUT);
        shuffleReadTimeout =
          job.getInt("mapreduce.reduce.shuffle.read.timeout", DEFAULT_READ_TIMEOUT);
        
        if (job.getCompressMapOutput()) {
          Class<? extends CompressionCodec> codecClass =
            job.getMapOutputCompressorClass(DefaultCodec.class);
          codec = ReflectionUtils.newInstance(codecClass, job);
          decompressor = CodecPool.getDecompressor(codec);
        }
      }
      
      /**
       * Fail the current file that we are fetching
       * @return were we currently fetching?
       */
      public synchronized boolean fail() {
        if (currentLocation != null) {
          finish(-1, CopyOutputErrorType.OTHER_ERROR);
          return true;
        } else {
          return false;
        }
      }
      
      /**
       * Get the current map output location.
       */
      public synchronized MapOutputLocation getLocation() {
        return currentLocation;
      }
      
      private synchronized void start(MapOutputLocation loc) {
        currentLocation = loc;
      }
      
      private synchronized void finish(long size, CopyOutputErrorType error) {
        if (currentLocation != null) {
          LOG.debug(getName() + " finishing " + currentLocation + " =" + size);
          synchronized (copyResultsOrNewEventsLock) {
            copyResults.add(new CopyResult(currentLocation, size, error));
            copyResultsOrNewEventsLock.notifyAll();
          }
          currentLocation = null;
        }
      }
      
      /** Loop forever and fetch map outputs as they become available.
       * The thread exits when it is interrupted by {@link ReduceTaskRunner}
       */
      @Override
      public void run() {
        while (true) {        
          try {
            MapOutputLocation loc = null;
            long size = -1;
            
            synchronized (scheduledCopies) {
              while (scheduledCopies.isEmpty()) {
                scheduledCopies.wait();
              }
              loc = scheduledCopies.remove(0);
            }
            CopyOutputErrorType error = CopyOutputErrorType.OTHER_ERROR;
            readError = false;
            try {
              shuffleClientMetrics.threadBusy();
              start(loc);
              size = copyOutput(loc);
              shuffleClientMetrics.successFetch();
              error = CopyOutputErrorType.NO_ERROR;
            } catch (IOException e) {
						LOG.warn(reduceId + " copy failed: " +
                       loc.getTaskAttemptId() + " from " + loc.getHost());
              LOG.warn(StringUtils.stringifyException(e));
              shuffleClientMetrics.failedFetch();
              if (readError) {
                error = CopyOutputErrorType.READ_ERROR;
              }
              // Reset 
              size = -1;
            } finally {
              shuffleClientMetrics.threadFree();
              finish(size, error);
            }
          } catch (InterruptedException e) { 
            break; // ALL DONE
          } catch (FSError e) {
					LOG.error("Task: " + reduceId + " - FSError: " + 
                      StringUtils.stringifyException(e));
            try {
						umbilical.fsError(reduceId, e.getMessage(), reduceTask.jvmContext);
            } catch (IOException io) {
              LOG.error("Could not notify TT of FSError: " + 
                      StringUtils.stringifyException(io));
            }
          } catch (Throwable th) {
					String msg = reduceId + " : Map output copy failure : " 
                         + StringUtils.stringifyException(th);
					reduceTask.reportFatalError(reduceId, th, msg);
          }
        }
        
        if (decompressor != null) {
          CodecPool.returnDecompressor(decompressor);
        }
          
      }
      
      /** Copies a a map output from a remote host, via HTTP. 
       * @param currentLocation the map output location to be copied
       * @return the path (fully qualified) of the copied file
       * @throws IOException if there is an error copying the file
       * @throws InterruptedException if the copier should give up
       */
      private long copyOutput(MapOutputLocation loc
                              ) throws IOException, InterruptedException {
        // check if we still need to copy the output from this location
        if (copiedMapOutputs.contains(loc.getTaskId()) || 
            obsoleteMapIds.contains(loc.getTaskAttemptId())) {
          return CopyResult.OBSOLETE;
        } 
 
        // a temp filename. If this file gets created in ramfs, we're fine,
        // else, we will check the localFS to find a suitable final location
        // for this path
			TaskAttemptID reduceId = ReduceCopier.this.reduceId;
        Path filename =
            new Path(String.format(
                MapOutputFile.REDUCE_INPUT_FILE_FORMAT_STRING,
                TaskTracker.OUTPUT, loc.getTaskId().getId()));

        // Copy the map output to a temp file whose name is unique to this attempt 
        Path tmpMapOutput = new Path(filename+"-"+id);
        
        // Copy the map output
        MapOutput mapOutput = getMapOutput(loc, tmpMapOutput,
                                           reduceId.getTaskID().getId());
        if (mapOutput == null) {
          throw new IOException("Failed to fetch map-output for " + 
                                loc.getTaskAttemptId() + " from " + 
                                loc.getHost());
        }
        
        // The size of the map-output
        long bytes = mapOutput.compressedSize;
        
        // lock the ReduceTask while we do the rename
			synchronized (reduceTask) {
          if (copiedMapOutputs.contains(loc.getTaskId())) {
            mapOutput.discard();
            return CopyResult.OBSOLETE;
          }

          // Special case: discard empty map-outputs
          if (bytes == 0) {
            try {
              mapOutput.discard();
            } catch (IOException ioe) {
              LOG.info("Couldn't discard output of " + loc.getTaskId());
            }
            
            // Note that we successfully copied the map-output
            noteCopiedMapOutput(loc.getTaskId());
            
            return bytes;
          }
          
          // Process map-output
          if (mapOutput.inMemory) {
            // Save it in the synchronized list of map-outputs
            mapOutputsFilesInMemory.add(mapOutput);
          } else {
            // Rename the temporary file to the final file; 
            // ensure it is on the same partition
            tmpMapOutput = mapOutput.file;
            filename = new Path(tmpMapOutput.getParent(), filename.getName());
            if (!localFileSys.rename(tmpMapOutput, filename)) {
              localFileSys.delete(tmpMapOutput, true);
              bytes = -1;
              throw new IOException("Failed to rename map output " + 
                  tmpMapOutput + " to " + filename);
            }

					synchronized (reduceTask.mapOutputFilesOnDisk) {        
              addToMapOutputFilesOnDisk(localFileSys.getFileStatus(filename));
            }
          }

          // Note that we successfully copied the map-output
          noteCopiedMapOutput(loc.getTaskId());
        }
        
        return bytes;
      }
      
      /**
       * Save the map taskid whose output we just copied.
		 * This function assumes that it has been synchronized on reduceTask.
       * 
       * @param taskId map taskid
       */
      private void noteCopiedMapOutput(TaskID taskId) {
        copiedMapOutputs.add(taskId);
			ramManager.setNumCopiedMapOutputs(reduceTask.getNumMaps() - copiedMapOutputs.size());
      }

      /**
       * Get the map output into a local file (either in the inmemory fs or on the 
       * local fs) from the remote server.
       * We use the file system so that we generate checksum files on the data.
       * @param mapOutputLoc map-output to be fetched
       * @param filename the filename to write the data into
       * @param connectionTimeout number of milliseconds for connection timeout
       * @param readTimeout number of milliseconds for read timeout
       * @return the path of the file that got created
       * @throws IOException when something goes wrong
       */
      private MapOutput getMapOutput(MapOutputLocation mapOutputLoc, 
                                     Path filename, int reduce)
      throws IOException, InterruptedException {
        // Connect
        URL url = mapOutputLoc.getOutputLocation();
        HttpURLConnection connection = (HttpURLConnection)url.openConnection();
        
        InputStream input = setupSecureConnection(mapOutputLoc, connection);
 
        // Validate response code
        int rc = connection.getResponseCode();
        if (rc != HttpURLConnection.HTTP_OK) {
          throw new IOException(
              "Got invalid response code " + rc + " from " + url +
              ": " + connection.getResponseMessage());
        }
 
        // Validate header from map output
        TaskAttemptID mapId = null;
        try {
          mapId =
            TaskAttemptID.forName(connection.getHeaderField(FROM_MAP_TASK));
        } catch (IllegalArgumentException ia) {
          LOG.warn("Invalid map id ", ia);
          return null;
        }
        TaskAttemptID expectedMapId = mapOutputLoc.getTaskAttemptId();
        if (!mapId.equals(expectedMapId)) {
          LOG.warn("data from wrong map:" + mapId +
              " arrived to reduce task " + reduce +
              ", where as expected map output should be from " + expectedMapId);
          return null;
        }
        
        long decompressedLength = 
          Long.parseLong(connection.getHeaderField(RAW_MAP_OUTPUT_LENGTH));  
        long compressedLength = 
          Long.parseLong(connection.getHeaderField(MAP_OUTPUT_LENGTH));

        if (compressedLength < 0 || decompressedLength < 0) {
          LOG.warn(getName() + " invalid lengths in map output header: id: " +
              mapId + " compressed len: " + compressedLength +
              ", decompressed len: " + decompressedLength);
          return null;
        }
        int forReduce =
          (int)Integer.parseInt(connection.getHeaderField(FOR_REDUCE_TASK));
        
        if (forReduce != reduce) {
          LOG.warn("data for the wrong reduce: " + forReduce +
              " with compressed len: " + compressedLength +
              ", decompressed len: " + decompressedLength +
              " arrived to reduce task " + reduce);
          return null;
        }
        if (LOG.isDebugEnabled()) {
          LOG.debug("header: " + mapId + ", compressed len: " + compressedLength +
              ", decompressed len: " + decompressedLength);
        }

        //We will put a file in memory if it meets certain criteria:
        //1. The size of the (decompressed) file should be less than 25% of 
        //    the total inmem fs
        //2. There is space available in the inmem fs
        
        // Check if this map-output can be saved in-memory
        boolean shuffleInMemory = ramManager.canFitInMemory(decompressedLength); 

        // Shuffle
        MapOutput mapOutput = null;
        if (shuffleInMemory) {
          if (LOG.isDebugEnabled()) {
            LOG.debug("Shuffling " + decompressedLength + " bytes (" + 
                compressedLength + " raw bytes) " + 
                "into RAM from " + mapOutputLoc.getTaskAttemptId());
          }

          mapOutput = shuffleInMemory(mapOutputLoc, connection, input,
                                      (int)decompressedLength,
                                      (int)compressedLength);
        } else {
          if (LOG.isDebugEnabled()) {
            LOG.debug("Shuffling " + decompressedLength + " bytes (" + 
                compressedLength + " raw bytes) " + 
                "into Local-FS from " + mapOutputLoc.getTaskAttemptId());
          }
          
          mapOutput = shuffleToDisk(mapOutputLoc, input, filename, 
              compressedLength);
        }
            
        return mapOutput;
      }
      
      private InputStream setupSecureConnection(MapOutputLocation mapOutputLoc, 
          URLConnection connection) throws IOException {

        // generate hash of the url
        String msgToEncode = 
          SecureShuffleUtils.buildMsgFrom(connection.getURL());
        String encHash = SecureShuffleUtils.hashFromString(msgToEncode, 
            jobTokenSecret);

        // put url hash into http header
        connection.setRequestProperty(
            SecureShuffleUtils.HTTP_HEADER_URL_HASH, encHash);
        
        InputStream input = getInputStream(connection, shuffleConnectionTimeout,
                                           shuffleReadTimeout); 

        // get the replyHash which is HMac of the encHash we sent to the server
        String replyHash = connection.getHeaderField(
            SecureShuffleUtils.HTTP_HEADER_REPLY_URL_HASH);
        if(replyHash==null) {
          throw new IOException("security validation of TT Map output failed");
        }
        if (LOG.isDebugEnabled())
          LOG.debug("url="+msgToEncode+";encHash="+encHash+";replyHash="
              +replyHash);
        // verify that replyHash is HMac of encHash
        SecureShuffleUtils.verifyReply(replyHash, encHash, jobTokenSecret);
        if (LOG.isDebugEnabled())
          LOG.debug("for url="+msgToEncode+" sent hash and receievd reply");
        return input;
      }

      /** 
       * The connection establishment is attempted multiple times and is given up 
       * only on the last failure. Instead of connecting with a timeout of 
       * X, we try connecting with a timeout of x < X but multiple times. 
       */
      private InputStream getInputStream(URLConnection connection, 
                                         int connectionTimeout, 
                                         int readTimeout) 
      throws IOException {
        int unit = 0;
        if (connectionTimeout < 0) {
          throw new IOException("Invalid timeout "
                                + "[timeout = " + connectionTimeout + " ms]");
        } else if (connectionTimeout > 0) {
          unit = (UNIT_CONNECT_TIMEOUT > connectionTimeout)
                 ? connectionTimeout
                 : UNIT_CONNECT_TIMEOUT;
        }
        // set the read timeout to the total timeout
        connection.setReadTimeout(readTimeout);
        // set the connect timeout to the unit-connect-timeout
        connection.setConnectTimeout(unit);
        while (true) {
          try {
            connection.connect();
            break;
          } catch (IOException ioe) {
            // update the total remaining connect-timeout
            connectionTimeout -= unit;

            // throw an exception if we have waited for timeout amount of time
            // note that the updated value if timeout is used here
            if (connectionTimeout == 0) {
              throw ioe;
            }

            // reset the connect timeout for the last try
            if (connectionTimeout < unit) {
              unit = connectionTimeout;
              // reset the connect time out for the final connect
              connection.setConnectTimeout(unit);
            }
          }
        }
        try {
          return connection.getInputStream();
        } catch (IOException ioe) {
          readError = true;
          throw ioe;
        }
      }

      private MapOutput shuffleInMemory(MapOutputLocation mapOutputLoc,
                                        URLConnection connection, 
                                        InputStream input,
                                        int mapOutputLength,
                                        int compressedLength)
      throws IOException, InterruptedException {
        // Reserve ram for the map-output
        boolean createdNow = ramManager.reserve(mapOutputLength, input);
      
        // Reconnect if we need to
        if (!createdNow) {
          // Reconnect
          try {
            connection = mapOutputLoc.getOutputLocation().openConnection();
            input = setupSecureConnection(mapOutputLoc, connection);
          } catch (IOException ioe) {
            LOG.info("Failed reopen connection to fetch map-output from " + 
                     mapOutputLoc.getHost());
            
            // Inform the ram-manager
            ramManager.closeInMemoryFile(mapOutputLength);
            ramManager.unreserve(mapOutputLength);
            
            throw ioe;
          }
        }

        IFileInputStream checksumIn = 
          new IFileInputStream(input,compressedLength);

        input = checksumIn;       
      
        // Are map-outputs compressed?
        if (codec != null) {
          decompressor.reset();
          input = codec.createInputStream(input, decompressor);
        }
      
        // Copy map-output into an in-memory buffer
        byte[] shuffleData = new byte[mapOutputLength];
        MapOutput mapOutput = 
          new MapOutput(mapOutputLoc.getTaskId(), 
                        mapOutputLoc.getTaskAttemptId(), shuffleData, compressedLength);
        
        int bytesRead = 0;
        try {
          int n = input.read(shuffleData, 0, shuffleData.length);
          while (n > 0) {
            bytesRead += n;
            shuffleClientMetrics.inputBytes(n);

            // indicate we're making progress
            reporter.progress();
            n = input.read(shuffleData, bytesRead, 
                           (shuffleData.length-bytesRead));
          }

          if (LOG.isDebugEnabled()) {
            LOG.debug("Read " + bytesRead + " bytes from map-output for " +
                mapOutputLoc.getTaskAttemptId());
          }

          input.close();
        } catch (IOException ioe) {
          LOG.info("Failed to shuffle from " + mapOutputLoc.getTaskAttemptId(), 
                   ioe);

          // Inform the ram-manager
          ramManager.closeInMemoryFile(mapOutputLength);
          ramManager.unreserve(mapOutputLength);
          
          // Discard the map-output
          try {
            mapOutput.discard();
          } catch (IOException ignored) {
            LOG.info("Failed to discard map-output from " + 
                     mapOutputLoc.getTaskAttemptId(), ignored);
          }
          mapOutput = null;
          
          // Close the streams
          IOUtils.cleanup(LOG, input);

          // Re-throw
          readError = true;
          throw ioe;
        }

        // Close the in-memory file
        ramManager.closeInMemoryFile(mapOutputLength);

        // Sanity check
        if (bytesRead != mapOutputLength) {
          // Inform the ram-manager
          ramManager.unreserve(mapOutputLength);
          
          // Discard the map-output
          try {
            mapOutput.discard();
          } catch (IOException ignored) {
            // IGNORED because we are cleaning up
            LOG.info("Failed to discard map-output from " + 
                     mapOutputLoc.getTaskAttemptId(), ignored);
          }
          mapOutput = null;

          throw new IOException("Incomplete map output received for " +
                                mapOutputLoc.getTaskAttemptId() + " from " +
                                mapOutputLoc.getOutputLocation() + " (" + 
                                bytesRead + " instead of " + 
                                mapOutputLength + ")"
          );
        }

        // TODO: Remove this after a 'fix' for HADOOP-3647
        if (LOG.isDebugEnabled()) {
          if (mapOutputLength > 0) {
            DataInputBuffer dib = new DataInputBuffer();
            dib.reset(shuffleData, 0, shuffleData.length);
            LOG.debug("Rec #1 from " + mapOutputLoc.getTaskAttemptId() + 
                " -> (" + WritableUtils.readVInt(dib) + ", " + 
                WritableUtils.readVInt(dib) + ") from " + 
                mapOutputLoc.getHost());
          }
        }
        
        return mapOutput;
      }
      
      private MapOutput shuffleToDisk(MapOutputLocation mapOutputLoc,
                                      InputStream input,
                                      Path filename,
                                      long mapOutputLength) 
      throws IOException {
        // Find out a suitable location for the output on local-filesystem
        Path localFilename = 
					reduceTask.lDirAlloc.getLocalPathForWrite(filename.toUri().getPath(), 
							mapOutputLength, reduceTask.conf);

        MapOutput mapOutput = 
          new MapOutput(mapOutputLoc.getTaskId(), mapOutputLoc.getTaskAttemptId(), 
							reduceTask.conf, localFileSys.makeQualified(localFilename), 
                        mapOutputLength);


        // Copy data to local-disk
        OutputStream output = null;
        long bytesRead = 0;
        try {
          output = rfs.create(localFilename);
          
          byte[] buf = new byte[64 * 1024];
          int n = -1;
          try {
            n = input.read(buf, 0, buf.length);
          } catch (IOException ioe) {
            readError = true;
            throw ioe;
          }
          while (n > 0) {
            bytesRead += n;
            shuffleClientMetrics.inputBytes(n);
            output.write(buf, 0, n);

            // indicate we're making progress
            reporter.progress();
            try {
              n = input.read(buf, 0, buf.length);
            } catch (IOException ioe) {
              readError = true;
              throw ioe;
            }
          }

          LOG.info("Read " + bytesRead + " bytes from map-output for " +
              mapOutputLoc.getTaskAttemptId());

          output.close();
          input.close();
        } catch (IOException ioe) {
          LOG.info("Failed to shuffle from " + mapOutputLoc.getTaskAttemptId(), 
                   ioe);

          // Discard the map-output
          try {
            mapOutput.discard();
          } catch (IOException ignored) {
            LOG.info("Failed to discard map-output from " + 
                mapOutputLoc.getTaskAttemptId(), ignored);
          }
          mapOutput = null;

          // Close the streams
          IOUtils.cleanup(LOG, input, output);

          // Re-throw
          throw ioe;
        }

        // Sanity check
        if (bytesRead != mapOutputLength) {
          try {
            mapOutput.discard();
          } catch (Exception ioe) {
            // IGNORED because we are cleaning up
            LOG.info("Failed to discard map-output from " + 
                mapOutputLoc.getTaskAttemptId(), ioe);
          } catch (Throwable t) {
					String msg = reduceId + " : Failed in shuffle to disk :" 
                         + StringUtils.stringifyException(t);
					reduceTask.reportFatalError(reduceId, t, msg);
          }
          mapOutput = null;

          throw new IOException("Incomplete map output received for " +
                                mapOutputLoc.getTaskAttemptId() + " from " +
                                mapOutputLoc.getOutputLocation() + " (" + 
                                bytesRead + " instead of " + 
                                mapOutputLength + ")"
          );
        }

        return mapOutput;

      }
      
    } // MapOutputCopier
    
    private boolean busyEnough(int numInFlight) {
      return numInFlight > maxInFlight;
    }
    
    
    public boolean fetchOutputs() throws IOException {

      int totalFailures = 0;
      int            numInFlight = 0, numCopied = 0;
      DecimalFormat  mbpsFormat = new DecimalFormat("0.00");
      final Progress copyPhase = 
        reduceTask.getProgress().phase();
      LocalFSMerger localFSMergerThread = null;
      InMemFSMergeThread inMemFSMergeThread = null;
      GetMapEventsThread getMapEventsThread = null;
      
		for (int i = 0; i < reduceTask.getNumMaps(); i++) {
        copyPhase.addPhase();       // add sub-phase per file
      }
      
      copiers = new ArrayList<MapOutputCopier>(numCopiers);
      
      // start all the copying threads
      for (int i=0; i < numCopiers; i++) {
			MapOutputCopier copier = new MapOutputCopier(reduceTask.conf, reporter, 
            reduceTask.getJobTokenSecret());
        copiers.add(copier);
        copier.start();
      }
      
      //start the on-disk-merge thread
      localFSMergerThread = new LocalFSMerger((LocalFileSystem)localFileSys);
      //start the in memory merger thread
      inMemFSMergeThread = new InMemFSMergeThread();
      localFSMergerThread.start();
      inMemFSMergeThread.start();
      
      // start the map events thread
      getMapEventsThread = new GetMapEventsThread();
      getMapEventsThread.start();
      
      // start the clock for bandwidth measurement
      long startTime = System.currentTimeMillis();
      long currentTime = startTime;
      long lastProgressTime = startTime;
      long lastOutputTime = 0;
      
        // loop until we get all required outputs
	while (copiedMapOutputs.size() < reduceTask.getNumMaps() && mergeThrowable == null) {
          int numEventsAtStartOfScheduling;
          synchronized (copyResultsOrNewEventsLock) {
            numEventsAtStartOfScheduling = numEventsFetched;
          }
          
          currentTime = System.currentTimeMillis();
          boolean logNow = false;
          if (currentTime - lastOutputTime > MIN_LOG_TIME) {
            lastOutputTime = currentTime;
            logNow = true;
          }
          if (logNow) {
				LOG.info(reduceId + " Need another " 
						+ (reduceTask.getNumMaps() - copiedMapOutputs.size()) + " map output(s) "
                   + "where " + numInFlight + " is already in progress");
          }

          // Put the hash entries for the failed fetches.
          Iterator<MapOutputLocation> locItr = retryFetches.iterator();

          while (locItr.hasNext()) {
            MapOutputLocation loc = locItr.next(); 
            List<MapOutputLocation> locList = 
              mapLocations.get(loc.getHost());
            
            // Check if the list exists. Map output location mapping is cleared 
            // once the jobtracker restarts and is rebuilt from scratch.
            // Note that map-output-location mapping will be recreated and hence
            // we continue with the hope that we might find some locations
            // from the rebuild map.
            if (locList != null) {
              // Add to the beginning of the list so that this map is 
              //tried again before the others and we can hasten the 
              //re-execution of this map should there be a problem
              locList.add(0, loc);
            }
          }

          if (retryFetches.size() > 0) {
				LOG.info(reduceId + ": " +  
                  "Got " + retryFetches.size() +
                  " map-outputs from previous failures");
          }
          // clear the "failed" fetches hashmap
          retryFetches.clear();

          // now walk through the cache and schedule what we can
          int numScheduled = 0;
          int numDups = 0;
          
          synchronized (scheduledCopies) {
  
            // Randomize the map output locations to prevent 
            // all reduce-tasks swamping the same tasktracker
            List<String> hostList = new ArrayList<String>();
            hostList.addAll(mapLocations.keySet()); 
            
            Collections.shuffle(hostList, this.random);
              
            Iterator<String> hostsItr = hostList.iterator();

            while (hostsItr.hasNext()) {
            
              String host = hostsItr.next();

              List<MapOutputLocation> knownOutputsByLoc = 
                mapLocations.get(host);

              // Check if the list exists. Map output location mapping is 
              // cleared once the jobtracker restarts and is rebuilt from 
              // scratch.
              // Note that map-output-location mapping will be recreated and 
              // hence we continue with the hope that we might find some 
              // locations from the rebuild map and add then for fetching.
              if (knownOutputsByLoc == null || knownOutputsByLoc.size() == 0) {
                continue;
              }
              
              //Identify duplicate hosts here
              if (uniqueHosts.contains(host)) {
                 numDups += knownOutputsByLoc.size(); 
                 continue;
              }

              Long penaltyEnd = penaltyBox.get(host);
              boolean penalized = false;
            
              if (penaltyEnd != null) {
                if (currentTime < penaltyEnd.longValue()) {
                  penalized = true;
                } else {
                  penaltyBox.remove(host);
                }
              }
              
              if (penalized)
                continue;

              synchronized (knownOutputsByLoc) {
              
                locItr = knownOutputsByLoc.iterator();
            
                while (locItr.hasNext()) {
              
                  MapOutputLocation loc = locItr.next();
              
                  // Do not schedule fetches from OBSOLETE maps
                  if (obsoleteMapIds.contains(loc.getTaskAttemptId())) {
                    locItr.remove();
                    continue;
                  }

                  uniqueHosts.add(host);
                  scheduledCopies.add(loc);
                  locItr.remove();  // remove from knownOutputs
                  numInFlight++; numScheduled++;

                  break; //we have a map from this host
                }
              }
            }
            scheduledCopies.notifyAll();
          }

          if (numScheduled > 0 || logNow) {
				LOG.info(reduceId + " Scheduled " + numScheduled +
                   " outputs (" + penaltyBox.size() +
                   " slow hosts and" + numDups + " dup hosts)");
          }

          if (penaltyBox.size() > 0 && logNow) {
            LOG.info("Penalized(slow) Hosts: ");
            for (String host : penaltyBox.keySet()) {
              LOG.info(host + " Will be considered after: " + 
                  ((penaltyBox.get(host) - currentTime)/1000) + " seconds.");
            }
          }

          // if we have no copies in flight and we can't schedule anything
          // new, just wait for a bit
          try {
            if (numInFlight == 0 && numScheduled == 0) {
              // we should indicate progress as we don't want TT to think
              // we're stuck and kill us
              reporter.progress();
              Thread.sleep(5000);
            }
          } catch (InterruptedException e) { } // IGNORE
          
          while (numInFlight > 0 && mergeThrowable == null) {
            if (LOG.isDebugEnabled()) {
              LOG.debug(reduceId + " numInFlight = " + 
                      numInFlight);
            }
            //the call to getCopyResult will either 
            //1) return immediately with a null or a valid CopyResult object,
            //                 or
            //2) if the numInFlight is above maxInFlight, return with a 
            //   CopyResult object after getting a notification from a 
            //   fetcher thread, 
            //So, when getCopyResult returns null, we can be sure that
            //we aren't busy enough and we should go and get more mapcompletion
            //events from the tasktracker
            CopyResult cr = getCopyResult(numInFlight, numEventsAtStartOfScheduling);

            if (cr == null) {
              break;
            }
            
            if (cr.getSuccess()) {  // a successful copy
              numCopied++;
              lastProgressTime = System.currentTimeMillis();
					reduceTask.reduceShuffleBytes.increment(cr.getSize());
                
              long secsSinceStart = 
                (System.currentTimeMillis()-startTime)/1000+1;
					float mbs = ((float)reduceTask.reduceShuffleBytes.getCounter())/(1024*1024);
              float transferRate = mbs/secsSinceStart;
                
              copyPhase.startNextPhase();
					copyPhase.setStatus("copy (" + numCopied + " of " + reduceTask.getNumMaps() 
                                  + " at " +
                                  mbpsFormat.format(transferRate) +  " MB/s)");
                
              // Note successful fetch for this mapId to invalidate
              // (possibly) old fetch-failures
              fetchFailedMaps.remove(cr.getLocation().getTaskId());
            } else if (cr.isObsolete()) {
              //ignore
					LOG.info(reduceId + 
                       " Ignoring obsolete copy result for Map Task: " + 
                       cr.getLocation().getTaskAttemptId() + " from host: " + 
                       cr.getHost());
            } else {
              retryFetches.add(cr.getLocation());
              
              // note the failed-fetch
              TaskAttemptID mapTaskId = cr.getLocation().getTaskAttemptId();
              TaskID mapId = cr.getLocation().getTaskId();
              
              totalFailures++;
              Integer noFailedFetches = 
                mapTaskToFailedFetchesMap.get(mapTaskId);
              noFailedFetches = 
                (noFailedFetches == null) ? 1 : (noFailedFetches + 1);
              mapTaskToFailedFetchesMap.put(mapTaskId, noFailedFetches);
					LOG.info("Task " + reduceId + ": Failed fetch #" + 
                       noFailedFetches + " from " + mapTaskId);

              if (noFailedFetches >= abortFailureLimit) {
                LOG.fatal(noFailedFetches + " failures downloading "
								+ reduceId + ".");
						umbilical.shuffleError(reduceId,
                                 "Exceeded the abort failure limit;"
										+ " bailing-out.", reduceTask.jvmContext);
              }
              
              checkAndInformJobTracker(noFailedFetches, mapTaskId,
                  cr.getError().equals(CopyOutputErrorType.READ_ERROR));

              // note unique failed-fetch maps
              if (noFailedFetches == maxFetchFailuresBeforeReporting) {
                fetchFailedMaps.add(mapId);
                  
                // did we have too many unique failed-fetch maps?
                // and did we fail on too many fetch attempts?
                // and did we progress enough
                //     or did we wait for too long without any progress?
               
                // check if the reducer is healthy
                boolean reducerHealthy = 
                    (((float)totalFailures / (totalFailures + numCopied)) 
                     < MAX_ALLOWED_FAILED_FETCH_ATTEMPT_PERCENT);
                
                // check if the reducer has progressed enough
                boolean reducerProgressedEnough = 
								(((float)numCopied / reduceTask.getNumMaps()) 
                     >= MIN_REQUIRED_PROGRESS_PERCENT);
                
                // check if the reducer is stalled for a long time
                // duration for which the reducer is stalled
                int stallDuration = 
                    (int)(System.currentTimeMillis() - lastProgressTime);
                // duration for which the reducer ran with progress
                int shuffleProgressDuration = 
                    (int)(lastProgressTime - startTime);
                // min time the reducer should run without getting killed
                int minShuffleRunDuration = 
                    (shuffleProgressDuration > maxMapRuntime) 
                    ? shuffleProgressDuration 
                    : maxMapRuntime;
                boolean reducerStalled = 
                    (((float)stallDuration / minShuffleRunDuration) 
                     >= MAX_ALLOWED_STALL_TIME_PERCENT);
                
                // kill if not healthy and has insufficient progress
                if ((fetchFailedMaps.size() >= maxFailedUniqueFetches ||
								fetchFailedMaps.size() == (reduceTask.getNumMaps() - copiedMapOutputs.size()))
                    && !reducerHealthy 
                    && (!reducerProgressedEnough || reducerStalled)) { 
                  LOG.fatal("Shuffle failed with too many fetch failures " + 
                            "and insufficient progress!" +
									"Killing task " + reduceId + ".");
							umbilical.shuffleError(reduceId, 
                                         "Exceeded MAX_FAILED_UNIQUE_FETCHES;"
											+ " bailing-out.", reduceTask.jvmContext);
                }

              }
                
              currentTime = System.currentTimeMillis();
              long currentBackOff = (long)(INITIAL_PENALTY *
                  Math.pow(PENALTY_GROWTH_RATE, noFailedFetches));

              penaltyBox.put(cr.getHost(), currentTime + currentBackOff);
					LOG.warn(reduceId + " adding host " +
                       cr.getHost() + " to penalty box, next contact in " +
                       (currentBackOff/1000) + " seconds");
            }
            uniqueHosts.remove(cr.getHost());
            numInFlight--;
          }
        }
        
        // all done, inform the copiers to exit
        exitGetMapEvents= true;
        try {
          getMapEventsThread.join();
          LOG.info("getMapsEventsThread joined.");
        } catch (InterruptedException ie) {
          LOG.info("getMapsEventsThread threw an exception: " +
              StringUtils.stringifyException(ie));
        }

        synchronized (copiers) {
          synchronized (scheduledCopies) {
            for (MapOutputCopier copier : copiers) {
              copier.interrupt();
            }
            copiers.clear();
          }
        }
        
        // copiers are done, exit and notify the waiting merge threads
		synchronized (reduceTask.mapOutputFilesOnDisk) {
          exitLocalFSMerge = true;
			reduceTask.mapOutputFilesOnDisk.notify();
        }
        
        ramManager.close();
        
        //Do a merge of in-memory files (if there are any)
        if (mergeThrowable == null) {
          try {
            // Wait for the on-disk merge to complete
            localFSMergerThread.join();
            LOG.info("Interleaved on-disk merge complete: " + 
						reduceTask.mapOutputFilesOnDisk.size() + " files left.");
            
            //wait for an ongoing merge (if it is in flight) to complete
            inMemFSMergeThread.join();
            LOG.info("In-memory merge complete: " + 
                     mapOutputsFilesInMemory.size() + " files left.");
            } catch (InterruptedException ie) {
				LOG.warn(reduceId +
                     " Final merge of the inmemory files threw an exception: " + 
                     StringUtils.stringifyException(ie));
            // check if the last merge generated an error
            if (mergeThrowable != null) {
              mergeThrowable = ie;
            }
            return false;
          }
        }
		return mergeThrowable == null && copiedMapOutputs.size() == reduceTask.getNumMaps();
    }
    
    // Notify the JobTracker
    // after every read error, if 'reportReadErrorImmediately' is true or
    // after every 'maxFetchFailuresBeforeReporting' failures
    protected void checkAndInformJobTracker(
        int failures, TaskAttemptID mapId, boolean readError) {
      if ((reportReadErrorImmediately && readError)
          || ((failures % maxFetchFailuresBeforeReporting) == 0)) {
			synchronized (reduceTask) {
				reduceTask.taskStatus.addFetchFailedMap(mapId);
          reporter.progress();
          LOG.info("Failed to fetch map-output from " + mapId +
                   " even after MAX_FETCH_RETRIES_PER_MAP retries... "
                   + " or it is a read error, "
                   + " reporting to the JobTracker");
        }
      }
    }



    private long createInMemorySegments(
        List<Segment<K, V>> inMemorySegments, long leaveBytes)
        throws IOException {
      long totalSize = 0L;
      synchronized (mapOutputsFilesInMemory) {
        // fullSize could come from the RamManager, but files can be
        // closed but not yet present in mapOutputsFilesInMemory
        long fullSize = 0L;
        for (MapOutput mo : mapOutputsFilesInMemory) {
          fullSize += mo.data.length;
        }
        while(fullSize > leaveBytes) {
          MapOutput mo = mapOutputsFilesInMemory.remove(0);
          totalSize += mo.data.length;
          fullSize -= mo.data.length;
          Reader<K, V> reader = 
            new InMemoryReader<K, V>(ramManager, mo.mapAttemptId,
                                     mo.data, 0, mo.data.length);
          Segment<K, V> segment = 
            new Segment<K, V>(reader, true);
          inMemorySegments.add(segment);
        }
      }
      return totalSize;
    }

    /**
     * Create a RawKeyValueIterator from copied map outputs. All copying
     * threads have exited, so all of the map outputs are available either in
     * memory or on disk. We also know that no merges are in progress, so
     * synchronization is more lax, here.
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
    @SuppressWarnings("unchecked")
	public RawKeyValueIterator createKVIterator(
        JobConf job, FileSystem fs, Reporter reporter) throws IOException {

      // merge config params
      Class<K> keyClass = (Class<K>)job.getMapOutputKeyClass();
      Class<V> valueClass = (Class<V>)job.getMapOutputValueClass();
      boolean keepInputs = job.getKeepFailedTaskFiles();
		final Path tmpDir = new Path(reduceId.toString());
      final RawComparator<K> comparator =
        (RawComparator<K>)job.getOutputKeyComparator();

      // segments required to vacate memory
      List<Segment<K,V>> memDiskSegments = new ArrayList<Segment<K,V>>();
      long inMemToDiskBytes = 0;
      if (mapOutputsFilesInMemory.size() > 0) {
        TaskID mapId = mapOutputsFilesInMemory.get(0).mapId;
        inMemToDiskBytes = createInMemorySegments(memDiskSegments,
            maxInMemReduce);
        final int numMemDiskSegments = memDiskSegments.size();
        if (numMemDiskSegments > 0 &&
					ioSortFactor > reduceTask.mapOutputFilesOnDisk.size()) {
          // must spill to disk, but can't retain in-mem for intermediate merge
          final Path outputPath =
						reduceTask.mapOutputFile.getInputFileForWrite(mapId, inMemToDiskBytes);
          final RawKeyValueIterator rIter = Merger.merge(job, fs,
              keyClass, valueClass, memDiskSegments, numMemDiskSegments,
						tmpDir, comparator, reporter, reduceTask.spilledRecordsCounter, null);
          final Writer writer = new Writer(job, fs, outputPath,
						keyClass, valueClass, reduceTask.codec, null);
          try {
            Merger.writeFile(rIter, writer, reporter, job);
            addToMapOutputFilesOnDisk(fs.getFileStatus(outputPath));
          } catch (Exception e) {
            if (null != outputPath) {
              fs.delete(outputPath, true);
            }
            throw new IOException("Final merge failed", e);
          } finally {
            if (null != writer) {
              writer.close();
            }
          }
          LOG.info("Merged " + numMemDiskSegments + " segments, " +
                   inMemToDiskBytes + " bytes to disk to satisfy " +
                   "reduce memory limit");
          inMemToDiskBytes = 0;
          memDiskSegments.clear();
        } else if (inMemToDiskBytes != 0) {
          LOG.info("Keeping " + numMemDiskSegments + " segments, " +
                   inMemToDiskBytes + " bytes in memory for " +
                   "intermediate, on-disk merge");
        }
      }

      // segments on disk
      List<Segment<K,V>> diskSegments = new ArrayList<Segment<K,V>>();
      long onDiskBytes = inMemToDiskBytes;
		Path[] onDisk = reduceTask.getMapFiles(fs, false);
      for (Path file : onDisk) {
        onDiskBytes += fs.getFileStatus(file).getLen();
			diskSegments.add(new Segment<K, V>(job, fs, file, reduceTask.codec, keepInputs));
      }
      LOG.info("Merging " + onDisk.length + " files, " +
               onDiskBytes + " bytes from disk");
      Collections.sort(diskSegments, new Comparator<Segment<K,V>>() {
        public int compare(Segment<K, V> o1, Segment<K, V> o2) {
          if (o1.getLength() == o2.getLength()) {
            return 0;
          }
          return o1.getLength() < o2.getLength() ? -1 : 1;
        }
      });

      // build final list of segments from merged backed by disk + in-mem
      List<Segment<K,V>> finalSegments = new ArrayList<Segment<K,V>>();
      long inMemBytes = createInMemorySegments(finalSegments, 0);
      LOG.info("Merging " + finalSegments.size() + " segments, " +
               inMemBytes + " bytes from memory into reduce");
      if (0 != onDiskBytes) {
        final int numInMemSegments = memDiskSegments.size();
        diskSegments.addAll(0, memDiskSegments);
        memDiskSegments.clear();
        RawKeyValueIterator diskMerge = Merger.merge(
					job, fs, keyClass, valueClass, reduceTask.codec, diskSegments,
            ioSortFactor, numInMemSegments, tmpDir, comparator,
					reporter, false, reduceTask.spilledRecordsCounter, null);
        diskSegments.clear();
        if (0 == finalSegments.size()) {
          return diskMerge;
        }
        finalSegments.add(new Segment<K,V>(
              new RawKVIteratorReader(diskMerge, onDiskBytes), true));
      }
      return Merger.merge(job, fs, keyClass, valueClass,
                   finalSegments, finalSegments.size(), tmpDir,
				comparator, reporter, reduceTask.spilledRecordsCounter, null);
    }

    class RawKVIteratorReader extends IFile.Reader<K,V> {

      private final RawKeyValueIterator kvIter;

      public RawKVIteratorReader(RawKeyValueIterator kvIter, long size)
          throws IOException {
			super(null, null, size, null, reduceTask.spilledRecordsCounter);
        this.kvIter = kvIter;
      }

      public boolean next(DataInputBuffer key, DataInputBuffer value)
          throws IOException {
        if (kvIter.next()) {
          final DataInputBuffer kb = kvIter.getKey();
          final DataInputBuffer vb = kvIter.getValue();
          final int kp = kb.getPosition();
          final int klen = kb.getLength() - kp;
          key.reset(kb.getData(), kp, klen);
          final int vp = vb.getPosition();
          final int vlen = vb.getLength() - vp;
          value.reset(vb.getData(), vp, vlen);
          bytesRead += klen + vlen;
          return true;
        }
        return false;
      }

      public long getPosition() throws IOException {
        return bytesRead;
      }

      public void close() throws IOException {
        kvIter.close();
      }
    }

    private CopyResult getCopyResult(int numInFlight, int numEventsAtStartOfScheduling) {
      boolean waitedForNewEvents = false;
      
      synchronized (copyResultsOrNewEventsLock) {
        while (copyResults.isEmpty()) {
          try {
            //The idea is that if we have scheduled enough, we can wait until
            // we hear from one of the copiers, or until there are new
            // map events ready to be scheduled
            if (busyEnough(numInFlight)) {
              // All of the fetcher threads are busy. So, no sense trying
              // to schedule more until one finishes.
              copyResultsOrNewEventsLock.wait();
            } else if (numEventsFetched == numEventsAtStartOfScheduling &&
                       !waitedForNewEvents) {
              // no sense trying to schedule more, since there are no
              // new events to even try to schedule.
              // We could handle this with a normal wait() without a timeout,
              // but since this code is being introduced in a stable branch,
              // we want to be very conservative. A 2-second wait is enough
              // to prevent the busy-loop experienced before.
              waitedForNewEvents = true;
              copyResultsOrNewEventsLock.wait(2000);
            } else {
              return null;
            }
          } catch (InterruptedException e) { }
        }
        return copyResults.remove(0);
      }    
    }
    
    private void addToMapOutputFilesOnDisk(FileStatus status) {
		synchronized (reduceTask.mapOutputFilesOnDisk) {
			reduceTask.mapOutputFilesOnDisk.add(status);
			reduceTask.mapOutputFilesOnDisk.notify();
      }
    }
    
    
    
    /** Starts merging the local copy (on disk) of the map's output so that
     * most of the reducer's input is sorted i.e overlapping shuffle
     * and merge phases.
     */
    private class LocalFSMerger extends Thread {
      private LocalFileSystem localFileSys;

      public LocalFSMerger(LocalFileSystem fs) {
        this.localFileSys = fs;
        setName("Thread for merging on-disk files");
        setDaemon(true);
      }

      @SuppressWarnings("unchecked")
      public void run() {
        try {
				LOG.info(reduceId + " Thread started: " + getName());
          while(!exitLocalFSMerge){
					synchronized (reduceTask.mapOutputFilesOnDisk) {
              while (!exitLocalFSMerge &&
								reduceTask.mapOutputFilesOnDisk.size() < (2 * ioSortFactor - 1)) {
							LOG.info(reduceId + " Thread waiting: " + getName());
							reduceTask.mapOutputFilesOnDisk.wait();
              }
            }
            if(exitLocalFSMerge) {//to avoid running one extra time in the end
              break;
            }
            List<Path> mapFiles = new ArrayList<Path>();
            long approxOutputSize = 0;
            int bytesPerSum = 
              reduceTask.getConf().getInt("io.bytes.per.checksum", 512);
					LOG.info(reduceId + "We have  " + 
							reduceTask.mapOutputFilesOnDisk.size() + " map outputs on disk. " +
                "Triggering merge of " + ioSortFactor + " files");
            // 1. Prepare the list of files to be merged. This list is prepared
            // using a list of map output files on disk. Currently we merge
            // io.sort.factor files into 1.
					synchronized (reduceTask.mapOutputFilesOnDisk) {
              for (int i = 0; i < ioSortFactor; ++i) {
							FileStatus filestatus = reduceTask.mapOutputFilesOnDisk.first();
							reduceTask.mapOutputFilesOnDisk.remove(filestatus);
                mapFiles.add(filestatus.getPath());
                approxOutputSize += filestatus.getLen();
              }
            }
            
            // sanity check
            if (mapFiles.size() == 0) {
                return;
            }
            
            // add the checksum length
            approxOutputSize += ChecksumFileSystem
                                .getChecksumLength(approxOutputSize,
                                                   bytesPerSum);
  
            // 2. Start the on-disk merge process
            Path outputPath = 
							reduceTask.lDirAlloc.getLocalPathForWrite(mapFiles.get(0).toString(), 
									approxOutputSize, reduceTask.conf)
              .suffix(".merged");
            Writer writer = 
							new Writer(reduceTask.conf,rfs, outputPath, 
									reduceTask.conf.getMapOutputKeyClass(), 
									reduceTask.conf.getMapOutputValueClass(),
									reduceTask.codec, null);
            RawKeyValueIterator iter  = null;
					Path tmpDir = new Path(reduceId.toString());
            try {
						iter = Merger.merge(reduceTask.conf, rfs,
								reduceTask.conf.getMapOutputKeyClass(),
								reduceTask.conf.getMapOutputValueClass(),
								reduceTask.codec, mapFiles.toArray(new Path[mapFiles.size()]), 
                                  true, ioSortFactor, tmpDir, 
								reduceTask.conf.getOutputKeyComparator(), reporter,
								reduceTask.spilledRecordsCounter, null);
              
						Merger.writeFile(iter, writer, reporter, reduceTask.conf);
              writer.close();
            } catch (Exception e) {
              localFileSys.delete(outputPath, true);
              throw new IOException (StringUtils.stringifyException(e));
            }
            
					synchronized (reduceTask.mapOutputFilesOnDisk) {
              addToMapOutputFilesOnDisk(localFileSys.getFileStatus(outputPath));
            }
            
					LOG.info(reduceId +
                     " Finished merging " + mapFiles.size() + 
                     " map output files on disk of total-size " + 
                     approxOutputSize + "." + 
                     " Local output file is " + outputPath + " of size " +
                     localFileSys.getFileStatus(outputPath).getLen());
            }
        } catch (Exception e) {
				LOG.warn(reduceId
                   + " Merging of the local FS files threw an exception: "
                   + StringUtils.stringifyException(e));
          if (mergeThrowable == null) {
            mergeThrowable = e;
          }
        } catch (Throwable t) {
				String msg = reduceId + " : Failed to merge on the local FS" 
                       + StringUtils.stringifyException(t);
				reduceTask.reportFatalError(reduceId, t, msg);
        }
      }
    }

    private class InMemFSMergeThread extends Thread {
      
      public InMemFSMergeThread() {
        setName("Thread for merging in memory files");
        setDaemon(true);
      }
      
      public void run() {
			LOG.info(reduceId + " Thread started: " + getName());
        try {
          boolean exit = false;
          do {
            exit = ramManager.waitForDataToMerge();
            if (!exit) {
              doInMemMerge();
            }
          } while (!exit);
        } catch (Exception e) {
				LOG.warn(reduceId +
                   " Merge of the inmemory files threw an exception: "
                   + StringUtils.stringifyException(e));
          ReduceCopier.this.mergeThrowable = e;
        } catch (Throwable t) {
				String msg = reduceId + " : Failed to merge in memory" 
                       + StringUtils.stringifyException(t);
				reduceTask.reportFatalError(reduceId, t, msg);
        }
      }
      
      @SuppressWarnings("unchecked")
      private void doInMemMerge() throws IOException{
        if (mapOutputsFilesInMemory.size() == 0) {
          return;
        }
        
        //name this output file same as the name of the first file that is 
        //there in the current list of inmem files (this is guaranteed to
        //be absent on the disk currently. So we don't overwrite a prev. 
        //created spill). Also we need to create the output file now since
        //it is not guaranteed that this file will be present after merge
        //is called (we delete empty files as soon as we see them
        //in the merge method)

        //figure out the mapId 
        TaskID mapId = mapOutputsFilesInMemory.get(0).mapId;

        List<Segment<K, V>> inMemorySegments = new ArrayList<Segment<K,V>>();
        long mergeOutputSize = createInMemorySegments(inMemorySegments, 0);
        int noInMemorySegments = inMemorySegments.size();

        Path outputPath =
					reduceTask.mapOutputFile.getInputFileForWrite(mapId, mergeOutputSize);

        Writer writer = 
					new Writer(reduceTask.conf, rfs, outputPath,
							reduceTask.conf.getMapOutputKeyClass(),
							reduceTask.conf.getMapOutputValueClass(),
							reduceTask.codec, null);

        RawKeyValueIterator rIter = null;
        try {
          LOG.info("Initiating in-memory merge with " + noInMemorySegments + 
                   " segments...");
          
				rIter = Merger.merge(reduceTask.conf, rfs,
						(Class<K>)reduceTask.conf.getMapOutputKeyClass(),
						(Class<V>)reduceTask.conf.getMapOutputValueClass(),
                               inMemorySegments, inMemorySegments.size(),
						new Path(reduceId.toString()),
						reduceTask.conf.getOutputKeyComparator(), reporter,
						reduceTask.spilledRecordsCounter, null);
          
          if (combinerRunner == null) {
					Merger.writeFile(rIter, writer, reporter, reduceTask.conf);
          } else {
            combineCollector.setWriter(writer);
            combinerRunner.combine(rIter, combineCollector);
          }
          writer.close();

				LOG.info(reduceId + 
              " Merge of the " + noInMemorySegments +
              " files in-memory complete." +
              " Local file is " + outputPath + " of size " + 
              localFileSys.getFileStatus(outputPath).getLen());
        } catch (Exception e) { 
          //make sure that we delete the ondisk file that we created 
          //earlier when we invoked cloneFileAttributes
          localFileSys.delete(outputPath, true);
          throw (IOException)new IOException
                  ("Intermediate merge failed").initCause(e);
        }

        // Note the output of the merge
        FileStatus status = localFileSys.getFileStatus(outputPath);
			synchronized (reduceTask.mapOutputFilesOnDisk) {
          addToMapOutputFilesOnDisk(status);
        }
      }
    }


  }

