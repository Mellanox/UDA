
#CPATH=hadoop-core-1.1.0-SNAPSHOT.jar:commons-logging-1.1.1.jar 
CPATH=hadoop-0.20.3-dev-core.jar:commons-logging-1.0.4.jar 

#CPATH=../hadoop-1.1.0-patched-v2/build/classes/:commons-logging-1.1.1.jar 
#CPATH=/tmp/hadoop-0.20.2-patched-v2/build/classes/:commons-logging-1.0.4.jar

all:
	rm -rf out
	mkdir -p out
	CLASSPATH=$(CPATH) javac -d out com/mellanox/hadoop/mapred/*.java
	jar -cvf uda-hadoop-0.20.2.jar -C out com
	rm -rf out

clean:
	rm -rf uda-hadoop-0.20.2.jar out
