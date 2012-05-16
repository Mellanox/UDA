#* 
AUTOMAKE_OPTIONS = subdir-objects

ACLOCAL_AMFLAGS = -I ../utils/m4
AM_LDFLAGS = -rdynamic
JDK = $(JAVA_HOME)
AM_CPPFLAGS = $(INCLUDE_DIR) -I$(top_srcdir) -I. -I$(top_srcdir)/include \
			  -I$(JDK)/include -I$(JDK)/include/linux \
			  -Wall -O3 -g -D_GNU_SOURCE

# Specify the source files for a library
# Append additional directory to the end of this list

lib_LTLIBRARIES = libhadoopUda.la

libhadoopUda_la_SOURCES = \
						include/atomic.h         \
						include/C2JNexus.h       \
						include/IOUtility.h      \
						include/LinkList.h       \
						include/MemCache.h       \
						include/NetlevComm.h     \
						include/AIOHandler.h     \
						MOFServer/IndexInfo.h    \
					   	MOFServer/MOFServlet.h \
					   	MOFServer/IndexInfo.cc  \
						MOFServer/MOFServlet.cc \
						MOFServer/MOFSupplierMain.cc \
					   	DataNet/RDMAClient.h \
					   	DataNet/RDMAComm.h \
					   	DataNet/RDMAServer.h \
					   	DataNet/RDMAClient.cc \
					   	DataNet/RDMAServer.cc \
					   	DataNet/RDMAComm.cc \
                        Merger/InputClient.h \
                        Merger/InputClient.cc \
                        CommUtils/IOUtility.cc \
                        CommUtils/atomic.cc \
                        CommUtils/C2JNexus.cc \
						CommUtils/AIOHandler.cc    \
					    Merger/MergeManager.h \
					    Merger/MergeManager.cc \
						Merger/StreamRW.h \
						Merger/StreamRW.cc \
						Merger/reducer.h \
						Merger/reducer.cc \
                        Merger/MergeQueue.h \
                        Merger/MergeQueue.cc \
                        Merger/NetMergerMain.cc \
                        UdaBridge.cc 

libhadoopUda_la_LIBADD =  -lpthread -libverbs -lrdmacm -laio

#support coverity
cov:
	PATH=/hpc/local/commercial/coverity/cov-sa/bin:$$PATH && rm -rf $(PWD)/cov-build && make clean && cov-build --dir $(PWD)/cov-build make all && cov-analyze --dir $(PWD)/cov-build && cov-format-errors --dir $(PWD)/cov-build

# vim: sw=4: ts=4: noet
