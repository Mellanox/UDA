#!/bin/bash

#exit upon error + trace info
set -e




usage() {
	echo "
usage: $0 <options>
  Required not-so-options:
     --distro-dir=DIR            path to distro specific files (debian/RPM)
     --build-dir=DIR             path to hive/build/dist
     --prefix=PREFIX             path to install into
     --uda-hadoop-conf-dir=DIR   path to existing hadoop installation that will use hadoop

  Optional options:
     --native-build-string       eg Linux-amd-64 (optional - no native installed if not set)
     ... [ see source for more similar options ]
  "
  exit 1
}

OPTS=$(getopt \
  -n $0 \
  -o '' \
  -l 'distro-dir:' \
  -l 'prefix:' \
  -l 'build-dir:' \
  -l 'native-build-string:' \
  -l 'installed-lib-dir:' \
  -l 'lib-dir:' \
  -l 'system-lib-dir:' \
  -l 'src-dir:' \
  -l 'etc-dir:' \
  -l 'doc-dir:' \
  -l 'man-dir:' \
  -l 'example-dir:' \
  -l 'apache-branch:' \
  -l 'uda-dir:' \
  -l 'uda-hadoop-conf-dir:' \
  -- "$@")

if [ $? != 0 ] ; then
    usage
fi

eval set -- "$OPTS"
while true ; do
    case "$1" in
        --uda-dir)
        UDA_DIR=$2 ; shift 2
        ;;
        --uda-hadoop-conf-dir)
        UDA_HADOOP_CONF_DIR=$2 ; shift 2
        ;;
        --prefix)
        PREFIX=$2 ; shift 2
        ;;
        --distro-dir)
        DISTRO_DIR=$2 ; shift 2
        ;;
        --lib-dir)
        LIB_DIR=$2 ; shift 2
        ;;
        --system-lib-dir)
        SYSTEM_LIB_DIR=$2 ; shift 2
        ;;
        --build-dir)
        BUILD_DIR=$2 ; shift 2
        ;;
        --native-build-string)
        NATIVE_BUILD_STRING=$2 ; shift 2
        ;;
        --doc-dir)
        DOC_DIR=$2 ; shift 2
        ;;
        --etc-dir)
        ETC_DIR=$2 ; shift 2
        ;;
        --installed-lib-dir)
        INSTALLED_LIB_DIR=$2 ; shift 2
        ;;
        --man-dir)
        MAN_DIR=$2 ; shift 2
        ;;
        --example-dir)
        EXAMPLE_DIR=$2 ; shift 2
        ;;
        --src-dir)
        SRC_DIR=$2 ; shift 2
        ;;
        --)
        shift ; break
        ;;
        *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
done


PREFIX=${PREFIX:-"/"} #avner's temp

for var in UDA_DIR UDA_HADOOP_CONF_DIR PREFIX BUILD_DIR; do
  if [ -z "$(eval "echo \$$var")" ]; then
    echo Missing param: $var
    usage
  fi
done

# UDA_HADOOP_CONF_DIR=${UDA_HADOOP_CONF_DIR:-$PREFIX/etc/hadoop/conf}
LIB_DIR=${LIB_DIR:-$PREFIX/usr/lib}
SYSTEM_LIB_DIR=${SYSTEM_LIB_DIR:-/usr/lib}
BIN_DIR=${BIN_DIR:-$PREFIX/usr/bin}
DOC_DIR=${DOC_DIR:-$PREFIX/usr/share/doc/hadoop}
MAN_DIR=${MAN_DIR:-$PREFIX/usr/man}
EXAMPLE_DIR=${EXAMPLE_DIR:-$DOC_DIR/examples}
SRC_DIR=${SRC_DIR:-$PREFIX/usr/src/uda}
ETC_DIR=${ETC_DIR:-$PREFIX/etc/uda}

INSTALLED_LIB_DIR=${INSTALLED_LIB_DIR:-/usr/lib/hadoop}
BUILD_SRC_DIR=./src



# Concatinate extra Java CLASSPATH elements, that are needed for UDA.
#mkdir -p /etc/hadoop/conf/

# echo "# add the following line to the end of your hadoop-env.sh file: \\" >> ${UDA_DIR}/uda-env.sh
# echo " #   if [ -f ${UDA_DIR}/uda-env.sh ]; then . ${UDA_DIR}/uda-env.sh; fi" >> ${UDA_DIR}/uda-env.sh
echo "export HADOOP_CLASSPATH=\$HADOOP_CLASSPATH:${UDA_DIR}/uda.jar" >> ${UDA_DIR}/uda-env.sh

# Source global definitions (unless it is already exists)
if [ -w $UDA_HADOOP_CONF_DIR/hadoop-env.sh ] && ! grep --quiet uda-env.sh  $UDA_HADOOP_CONF_DIR/hadoop-env.sh ; then
	echo "if [ -f ${UDA_DIR}/uda-env.sh ]; then . ${UDA_DIR}/uda-env.sh; fi" >> $UDA_HADOOP_CONF_DIR/hadoop-env.sh
fi



