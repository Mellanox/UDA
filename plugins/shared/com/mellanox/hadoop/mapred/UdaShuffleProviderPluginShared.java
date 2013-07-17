
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
import java.util.List;
import java.util.List;
import java.util.ArrayList;
import org.apache.hadoop.mapred.JobConf;
import org.apache.commons.logging.Log;

class UdaShuffleProviderPluginShared{

	static void buildCmdParams(List<String> params, JobConf jobConf) {
		params.clear();
		
		params.add("-w");
		params.add(jobConf.get("mapred.rdma.wqe.per.conn", "256"));
		params.add("-r");
		params.add(jobConf.get("mapred.rdma.cma.port", "9011"));      
		params.add("-m");
		params.add("1");
		
		params.add("-g");
		params.add(System.getProperty("hadoop.log.dir"));
		
		params.add("-s");
		params.add(jobConf.get("mapred.rdma.buf.size", "1024"));
	}


	static void close(Log LOG) {
		List<String> params = new ArrayList<String>();
		String msg = UdaCmd.formCmd(UdaCmd.EXIT_COMMAND, params);
		LOG.info("UDA: sending EXIT_COMMAND");    	  
		UdaBridge.doCommand(msg);        
	}
}