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
import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.RandomAccessFile;
import java.net.InetSocketAddress;
import java.net.URL;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;

import javax.crypto.SecretKey;

import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.LocalDirAllocator;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.DataInputByteBuffer;
import org.apache.hadoop.io.DataOutputBuffer;
import org.apache.hadoop.security.token.Token;
import org.apache.hadoop.yarn.api.records.ApplicationId;
import org.apache.hadoop.yarn.server.nodemanager.containermanager.AuxServices;
import org.apache.hadoop.yarn.server.nodemanager.containermanager.localizer.ContainerLocalizer;
import org.apache.hadoop.yarn.util.ConverterUtils;
import org.apache.hadoop.yarn.util.Records;
import org.apache.hadoop.mapred.JobID;
import org.apache.hadoop.mapreduce.security.token.JobTokenIdentifier;

import org.apache.hadoop.yarn.server.api.ApplicationInitializationContext;
import org.apache.hadoop.yarn.server.api.ApplicationTerminationContext;
import org.apache.hadoop.yarn.server.api.AuxiliaryService;

public class UdaShuffleHandler extends AuxiliaryService {

	private static final Log LOG = LogFactory.getLog(UdaShuffleHandler.class.getCanonicalName());
 
  private UdaPluginSH rdmaChannel;

  private Configuration config;

  
  public static final String MAPREDUCE_RDMA_SHUFFLE_SERVICEID =
      "uda.shuffle";

  private static final Map<String,String> userRsrc =
    new ConcurrentHashMap<String,String>();

  public UdaShuffleHandler() {
	  super("rdmashuffle");
	  LOG.info("c-tor of UdaShuffleHandler");
  }


  @Override
  public void initializeApplication(ApplicationInitializationContext context) {
	  LOG.info("starting initializeApplication of UdaShuffleHandler");

    String user = context.getUser();
    ApplicationId appId = context.getApplicationId();

    JobID jobId = new JobID(Long.toString(appId.getClusterTimestamp()), appId.getId());
//	  rdmaChannel = new UdaPluginSH(conf, user, jobId);	  
	  rdmaChannel.addJob(user, jobId);
	  LOG.info("finished initializeApplication of UdaShuffleHandler");
  }

  @Override
  public void stopApplication(ApplicationTerminationContext context) {
    ApplicationId appId = context.getApplicationId();
   LOG.info("stopApplication of UdaShuffleHandler");
   JobID jobId = new JobID(Long.toString(appId.getClusterTimestamp()), appId.getId());
   rdmaChannel.removeJob(jobId);
   LOG.info("stopApplication of UdaShuffleHandler is done");
		
  }

 //method of AbstractService
  @Override
  public synchronized void init(Configuration conf) {
  LOG.info("init of UdaShuffleHandler");
	 this.config = conf;
    super.init(new Configuration(conf));

  }

  //method of AbstractService
  @Override
  public synchronized void start() {
    LOG.info("start of UdaShuffleHandler");
    rdmaChannel = new UdaPluginSH(config);	  
	super.start();
	LOG.info("start of UdaShuffleHandler is done");
  }
  
  
  //method of AbstractService
  @Override
  public synchronized void stop() {
	  LOG.info("stop of UdaShuffleHandler");
	  rdmaChannel.close();
	  super.stop();
	  LOG.info("stop of UdaShuffleHandler is done");
  }
  
  public static ByteBuffer serializeServiceData(Token<JobTokenIdentifier> jobToken) throws IOException {
    //TODO these bytes should be versioned
    DataOutputBuffer jobToken_dob = new DataOutputBuffer();
    jobToken.write(jobToken_dob);
    return ByteBuffer.wrap(jobToken_dob.getData(), 0, jobToken_dob.getLength());
  }
 
  @Override
  public synchronized ByteBuffer getMetaData() {
/*		
    try {
      return serializeMetaData(port);
    } catch (IOException e) {
      LOG.error("Error during getMeta", e);
      // TODO add API to AuxiliaryServices to report failures
      return null;
    }
//*/		
    return null;
  }
 }

  
