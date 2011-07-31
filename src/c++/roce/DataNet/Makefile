TESTS = Roce_Rdma_Server 
UTILS = 

all: ${TESTS} ${UTILS}

CC = g++
CFLAGS += -Wall -g -D_GNU_SOURCE -O2
EXTRA_FILES =  
EXTRA_HEADERS = 
#The following seems to help GNU make on some platforms
LOADLIBES += -L/usr/ofed-1.4.2/lib64 
LDFLAGS += -I/usr/ofed-1.4.2/include
#LDFLAGS += pthread 

${TESTS}: LOADLIBES += -libverbs -lrdmacm

${TESTS} ${UTILS}: %: %.cc ${EXTRA_FILES} ${EXTRA_HEADERS}
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) $< ${EXTRA_FILES} $(LOADLIBES) $(LDLIBS) -o $@
clean:
	$(foreach fname,${TESTS} ${UTILS}, rm -f ${fname})
.DELETE_ON_ERROR:
.PHONY: all clean
