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
