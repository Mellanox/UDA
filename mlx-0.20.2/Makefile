
CPATH=hadoop-core-1.1.0-SNAPSHOT.jar:../../build/classes/org/apache/hadoop/mapred/:commons-logging-1.1.1.jar 
#CPATH=/volt/avnerb/workspace/hadoop-1.1.0-patched-v2/build/classes/:commons-logging-1.1.1.jar 
#CPATH=/volt/avnerb/workspace/hadoop-0.20.2-patched/build/classes/:commons-logging-1.1.1.jar

all:
	rm -rf out
	mkdir -p out
	CLASSPATH=$(CPATH) javac -d out com/mellanox/hadoop/mapred/*.java
	jar -cvf uda.jar -C out com
	rm -rf out

clean:
	rm -rf uda.jar out
