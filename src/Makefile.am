#* 
#* Copyright (c) 2010-2011. 
#* Parallel Architecture and System Lab, Auburn University
#*
#* Point of Contact:
#*   Weikuan Yu   (wkyu@auburn.edu)
#*
#* Contributors:
#*   Yandong Wang (yzw0025@auburn.edu)
#*   Xinyu Que    (xzq0003@auburn.edu)
#*   Bin Wang     (bzw0012@auburn.edu)
#*   Adarsh Jain  (asj0006@auburn.edu)
#*
#* Licensed under the Apache License, Version 2.0 (the "License");
#* you may not use this file except in compliance with the License.
#* You may obtain a copy of the License at
#*
#*    http://www.apache.org/licenses/LICENSE-2.0
#*
#* Unless required by applicable law or agreed to in writing, software
#* distributed under the License is distributed on an "AS IS" BASIS,
#* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#* See the License for the specific language governing permissions and
#* limitations under the License.
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
#noinst_LTLIBRARIES = libhadoopUda.la

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

						
#libhadoopUda_la_LDFLAGS = -module

libhadoopUda_la_LIBADD =  -lpthread -libverbs -lrdmacm -laio
#libhadoopUda_LDADD =  -lpthread -libverbs -lrdmacm -laio

# Two main binary programs will be created
# These programs will borrow all functions from the library
bin_PROGRAMS = MOFSupplier NetMerger

LDADD = -lhadoopUda -lpthread -libverbs -lrdmacm -laio
#MOFSupplier_LDFLAGS = -lhadoopUda
#NetMerger_LDFLAGS = -lhadoopUda

MOFSupplier_SOURCES = MOFSupplier.cc
NetMerger_SOURCES = NetMerger.cc

#support coverity
cov:
	PATH=/hpc/local/commercial/coverity/cov-sa/bin:$$PATH && rm -rf $(PWD)/cov-build && make clean && cov-build --dir $(PWD)/cov-build make all && cov-analyze --dir $(PWD)/cov-build && cov-format-errors --dir $(PWD)/cov-build

# vim: sw=4: ts=4: noet
