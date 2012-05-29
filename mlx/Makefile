
include makefile.mk
#CBASE=/volt/avnerb/workspace/uda/hadoop-1.1.0-uda/build/hadoop-1.1.0-SNAPSHOT/
#CPATH=.:$(CBASE)/hadoop-core-1.1.0-SNAPSHOT.jar:$(CBASE)/lib/commons-logging-1.1.1.jar

all:
	rm -rf out
	mkdir -p out
	CLASSPATH=$(CPATH) javac -d out com/mellanox/hadoop/mapred/*.java
	jar -cvf uda.jar -C out com
	rm -rf out

clean:
	rm -rf uda.jar out



