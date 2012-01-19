MAIN_FILE=JniTest
JDK = /usr/lib64/java/jdk1.6.0_25/
CFLAGS += -g -fPIC -I$(JDK)/include -I$(JDK)/include/linux
CXXFLAGS += $(CFLAGS)
NATIVE_LIB = lib$(MAIN_FILE).so
OBJS = $(MAIN_FILE).o

HFILE = org_apache_hadoop_mapred_$(MAIN_FILE).h
FQCN = org.apache.hadoop.mapred.$(MAIN_FILE)
MAIN_PATH = org/apache/hadoop/mapred/$(MAIN_FILE)

all: $(NATIVE_LIB) 

.SUFFIXES: .java .class .cpp .o .h .so

$(MAIN_PATH).class:
	$(JDK)/bin/javac $(MAIN_PATH).java

$(HFILE): $(MAIN_PATH).class
	$(JDK)/bin/javah -jni $(FQCN)

$(MAIN_FILE).o : $(HFILE)

$(NATIVE_LIB): $(OBJS)
	g++ -shared $(OBJS) -o $@

clean:
	rm -f *.so *.o $(MAIN_PATH).class $(HFILE)

test:
	LD_LIBRARY_PATH=. $(JDK)/bin/java $(FQCN)
