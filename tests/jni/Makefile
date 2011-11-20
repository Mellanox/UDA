MAIN_FILE=JniTest
JDK = /usr/lib/jvm/java-1.6.0-openjdk-1.6.0.0.x86_64/
CFLAGS += -c -g -fPIC -I$(JDK)/include -I$(JDK)/include/linux
CXXFLAGS += $(CFLAGS)
NATIVE_LIB = lib$(MAIN_FILE).so
OBJS = $(MAIN_FILE).o

all: $(NATIVE_LIB) $(MAIN_FILE).class


.SUFFIXES: .java .class .cpp .o .so


.java.class:
	$(JDK)/bin/javac $<

.class.h:
	$(JDK)/bin/javah -jni $(<:%.class=%)

$(MAIN_FILE).o : $(MAIN_FILE).h


$(NATIVE_LIB): $(OBJS)
	g++ -shared $(OBJS) -o $@

clean:
	rm -f *.so *.o *.class $(MAIN_FILE).h

test:
	LD_LIBRARY_PATH=. $(JDK)/bin/java $(MAIN_FILE)
