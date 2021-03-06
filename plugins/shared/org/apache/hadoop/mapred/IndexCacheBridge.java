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

package org.apache.hadoop.mapred;

import java.io.IOException;
import org.apache.hadoop.fs.Path;

/**
 *This class is an accessible wrapper around the vanilla hadoop's IndexCache
*/
public class IndexCacheBridge extends IndexCache{
  public IndexCacheBridge(JobConf conf) {
		super(conf);
	}
	
  public IndexRecordBridge getIndexInformationBridge(String mapId, int reduce,
      Path fileName, String expectedIndexOwner) throws IOException {
				
				IndexRecord indexRecord = super.getIndexInformation(mapId, reduce, fileName, expectedIndexOwner);			
				return new IndexRecordBridge(indexRecord);
	}	
}
