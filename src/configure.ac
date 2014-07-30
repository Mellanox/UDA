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

AC_PREREQ(2.59)
AC_INIT([libuda], [3.1], support@mellanox.com)
AC_CONFIG_HEADER([config.h])
AC_PREFIX_DEFAULT([`pwd`/bin])

AC_PROG_LIBTOOL
AM_PROG_LIBTOOL

#USE_HADOOP_UTILS
#HADOOP_RDMA_SETUP
#CHECK_INSTALL_CFLAG

define(ver_svn, esyscmd(git rev-list HEAD | wc -l ))
define(vers, esyscmd(cat ../release | tr -d '\n'))
syscmd(echo "version:"vers  > ../ver.txt)
syscmd(echo "revison:"ver_svn >> ../ver.txt)
syscmd(echo "c code complied on the:"`date` >> ../ver.txt)
syscmd(echo "compiled on:"`hostname` >> ../ver.txt)
syscmd(touch ltmain.sh) #TODO: check if can be removed
VERSION=vers.ver_svn
CXXFLAGS="-DVERSION_UDA=$VERSION"


# Generates Makefile from Makefile.am. Modify when new subdirs are added.
# Change Makefile.am also to add subdirectly.
AM_INIT_AUTOMAKE(foreign no-dist)


##AC_CONFIG_FILES([Makefile MOFServer/Makefile])
AC_CONFIG_FILES([Makefile])

AC_CONFIG_MACRO_DIR([./build/utils/m4])

AC_CANONICAL_BUILD
AC_CANONICAL_HOST

#AC_ARG_WITH([rdma-path], 
#	[AS_HELP_STRING([--with-rdma], 
#	    [location of a RDMA installation, defaults to /usr/include/])],
#       	[RDMA_INCPATH="-I$withval"],
#       	[RDMA_INCPATH='-I/usr/include']
#	)
#AC_SUBST([RDMA_INCPATH])
#
AC_CHECK_HEADERS([infiniband/verbs_exp.h],AC_MSG_NOTICE([infiniband/verbs_exp.h exists]),AC_MSG_NOTICE([infiniband/verbs_exp.h doesnt exist]))
#AC_CHECK_HEADERS([rdma/rdma_cma.h])
#
#AC_CHECK_LIB (libibverbs, ibv_post_send, ,
#	AC_MSG_ERROR([Can't find -libverbs. Please install libibverbs first.])
#	)
#
#AC_CHECK_LIB (librdmacm, rdma_connect, ,
#	AC_MSG_ERROR([Can't find -lrdmacm.  Please install rdmacm first.])
#	)

# Checks for programs.
AC_PROG_CC
AM_PROG_CC_C_O
AC_PROG_CXX

# Checks for header files.
# AC_LANG(C++)
AC_CHECK_HEADERS([unistd.h])

# Checks for typedefs, structures, and compiler characteristics.
AC_TYPE_OFF_T
AC_TYPE_SIZE_T

# Checks for library functions.
AC_CHECK_FUNCS([strdup strerror strtoul mkdir uname])
AC_CHECK_HEADERS([fcntl.h])
AC_FUNC_STRERROR_R
AC_C_CONST
AC_C_VOLATILE
AC_FUNC_MALLOC
AC_HEADER_STDBOOL


AC_CHECK_HEADERS([snappy-c.h], AC_COMPUTE_NEEDED_DSO(snappy,HADOOP_SNAPPY_LIBRARY), AC_MSG_WARN(Snappy headers were not found... building without snappy.))
AC_OUTPUT
