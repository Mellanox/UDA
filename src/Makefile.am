#
# Copyright (C) 2012 Auburn University
# Copyright (C) 2012 Mellanox Technologies
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at:
#  
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, 
# either express or implied. See the License for the specific language 
# governing permissions and  limitations under the License.
#
#

#* 
AUTOMAKE_OPTIONS = subdir-objects

ACLOCAL_AMFLAGS = -I ./build/utils/m4
AM_LDFLAGS = -rdynamic
JDK = $(JAVA_HOME)
AM_CPPFLAGS = $(INCLUDE_DIR) -I$(top_srcdir) -I. -I$(top_srcdir)/include \
			  -I$(JDK)/include -I$(JDK)/include/linux -std=gnu++0x \
			  -Wall -Werror -Wno-invalid-offsetof -O3 -g -D_GNU_SOURCE

# Specify the source files for a library
# Append additional directory to the end of this list

lib_LTLIBRARIES = libuda.la

libuda_la_SOURCES =		MOFServer/IndexInfo.cc \
						MOFServer/MOFServlet.cc \
						MOFServer/MOFSupplierMain.cc \
						DataNet/RDMAClient.cc \
						DataNet/RDMAServer.cc \
						DataNet/RDMAComm.cc \
						CommUtils/IOUtility.cc \
						CommUtils/atomic.cc \
						CommUtils/C2JNexus.cc \
						CommUtils/AIOHandler.cc \
						CommUtils/UdaUtil.cc \
						Merger/MergeManager.cc \
						Merger/StreamRW.cc \
						Merger/reducer.cc \
						Merger/MergeQueue.cc \
						Merger/NetMergerMain.cc \
						Merger/DecompressorWrapper.cc \
						Merger/CompareFunc.cc \
						Merger/LzoDecompressor.cc \
						Merger/SnappyDecompressor.cc \
						AsyncIO/AbstractReader.cc \
						AsyncIO/AsyncReaderManager.cc \
						AsyncIO/AsyncReaderThread.cc \
						UdaBridge.cc
						
libuda_la_LIBADD =  -lpthread -libverbs -lrdmacm -laio

#support coverity
cov:
	PATH=/hpc/local/commercial/coverity/cov-sa/bin:$$PATH && rm -rf $(PWD)/cov-build && make clean && cov-build --dir $(PWD)/cov-build make all && cov-analyze --dir $(PWD)/cov-build && cov-format-errors --dir $(PWD)/cov-build
