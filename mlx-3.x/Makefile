
#CPATH=hadoop-core-1.1.0-SNAPSHOT.jar:commons-logging-1.1.1.jar 
#CPATH=../hadoop-1.1.0-patched-v2/build/classes/:commons-logging-1.1.1.jar 
CBASE=../hadoop-dist/target/hadoop-3.0.0-SNAPSHOT/share/hadoop/
#CPATH=.:$(CBASE)/common/hadoop-common-3.0.0-SNAPSHOT.jar:$(CBASE)/common/lib/commons-logging-1.1.1.jar:$(CBASE)/mapreduce/hadoop-mapreduce-client-core-3.0.0-SNAPSHOT.jar:$(CBASE)/mapreduce/hadoop-yarn-server-nodemanager-3.0.0-SNAPSHOT.jar:$(CBASE)/mapreduce/hadoop-yarn-common-3.0.0-SNAPSHOT.jar:$(CBASE)/mapreduce/hadoop-yarn-api-3.0.0-SNAPSHOT.jar:$(CBASE)/mapreduce/hadoop-mapreduce-client-core-3.0.0-SNAPSHOT.jar
CPATH=.:hadoop-common-3.0.0-SNAPSHOT.jar:commons-logging-1.1.1.jar:hadoop-mapreduce-client-core-3.0.0-SNAPSHOT.jar:hadoop-yarn-server-nodemanager-3.0.0-SNAPSHOT.jar:hadoop-yarn-common-3.0.0-SNAPSHOT.jar:hadoop-yarn-api-3.0.0-SNAPSHOT.jar:hadoop-mapreduce-client-core-3.0.0-SNAPSHOT.jar

all:
	rm -rf out
	mkdir -p out
#	CLASSPATH=$(CPATH) javac -d out com/mellanox/hadoop/mapred/*.java
	CLASSPATH=$(CPATH) javac -d out com/mellanox/hadoop/mapred/UdaBridge.java com/mellanox/hadoop/mapred/UdaPlugin.java com/mellanox/hadoop/mapred/UdaShuffleConsumerPlugin.java
	jar -cvf uda-hadoop-3.x.jar -C out com
	rm -rf out

clean:
	rm -rf uda-hadoop-3.x.jar out
