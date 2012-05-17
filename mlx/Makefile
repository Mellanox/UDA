
CBASE=/volt/avnerb/workspace/uda/hadoop-1.0.2-uda/build/UDA-2.1.0-HADOOP-1.0.2/
CPATH=.:$(CBASE)/hadoop-core-1.0.2.jar:$(CBASE)/lib/commons-logging-1.1.1.jar

all:
	rm -rf out
	mkdir -p out
	CLASSPATH=$(CPATH) javac -d out com/mellanox/hadoop/mapred/*.java
	jar -cvf uda.jar -C out com

clean:
	rm -rf uda.jar out



