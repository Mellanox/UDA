#
# Copyright (C) 2012 Auburn University
# Copyright (C) 2012 Mellanox Technologies
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at:
#  
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, 
# either express or implied. See the License for the specific language 
# governing permissions and  limitations under the License.
#
#

#CPATH=hadoop-core-1.1.0-SNAPSHOT.jar:commons-logging-1.1.1.jar 
#CPATH=../hadoop-1.1.0-patched-v2/build/classes/:commons-logging-1.1.1.jar 
CBASE=../hadoop-dist/target/hadoop-3.0.0-SNAPSHOT/share/hadoop/
#CPATH=.:$(CBASE)/common/hadoop-common-3.0.0-SNAPSHOT.jar:$(CBASE)/common/lib/commons-logging-1.1.1.jar:$(CBASE)/mapreduce/hadoop-mapreduce-client-core-3.0.0-SNAPSHOT.jar:$(CBASE)/mapreduce/hadoop-yarn-server-nodemanager-3.0.0-SNAPSHOT.jar:$(CBASE)/mapreduce/hadoop-yarn-common-3.0.0-SNAPSHOT.jar:$(CBASE)/mapreduce/hadoop-yarn-api-3.0.0-SNAPSHOT.jar:$(CBASE)/mapreduce/hadoop-mapreduce-client-core-3.0.0-SNAPSHOT.jar
CPATH=.:hadoop-common-3.0.0-SNAPSHOT.jar:commons-logging-1.1.1.jar:hadoop-mapreduce-client-core-3.0.0-SNAPSHOT.jar:hadoop-yarn-server-nodemanager-3.0.0-SNAPSHOT.jar:hadoop-yarn-common-3.0.0-SNAPSHOT.jar:hadoop-yarn-api-3.0.0-SNAPSHOT.jar:hadoop-mapreduce-client-core-3.0.0-SNAPSHOT.jar

FILES=com/mellanox/hadoop/mapred/*.java org/apache/hadoop/mapred/*.java ../shared/com/mellanox/hadoop/mapred/*.java ../shared/org/apache/hadoop/mapred/*.java
TARGET=uda-hadoop-3.x.jar

all: $(TARGET)

$(TARGET):$(FILES)
	rm -rf out
	mkdir -p out
	CLASSPATH=$(CPATH) javac -Xlint -d out -sourcepath ../shared/:. $(FILES)
	jar -cvf $(TARGET) -C out com -C out org
	rm -rf out

clean:
	rm -rf $(TARGET) out
