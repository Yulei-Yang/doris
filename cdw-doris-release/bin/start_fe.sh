#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

curdir=$(dirname "$0")
curdir=$(
    cd "$curdir"
    pwd
)

OPTS=$(getopt \
    -n $0 \
    -o '' \
    -l 'daemon' \
    -l 'helper:' \
    -- "$@")

eval set -- "$OPTS"

RUN_DAEMON=0
HELPER=
while true; do
    case "$1" in
    --daemon)
        RUN_DAEMON=1
        shift
        ;;
    --helper)
        HELPER=$2
        shift 2
        ;;
    --)
        shift
        break
        ;;
    *)
	echo "Error params for this script!"
        exit 1
        ;;
    esac
done

export DORIS_HOME=$(
    cd "$curdir/.."
    pwd
)

while read -r line; do
    envline="$(echo "${line}" | sed 's/[[:blank:]]*=[[:blank:]]*/=/g' | sed 's/^[[:blank:]]*//g' || true)"
    envline1="$(echo $envline | egrep "^[[:upper:]]([[:upper:]]|_|[[:digit:]])*=" || true)"
    envline2="$(echo $envline | egrep "meta_dir|tmp_dir" || true)"
    if [[ $envline1 == *"="* ]]; then
        envline1="$(eval "echo ${envline1}")"
        eval 'export "$envline1"'
    elif [[ $envline2 == *"="* ]]; then
        envline2="$(eval "echo ${envline2}")"
        eval 'export "$envline2"'
    fi
done <"${DORIS_HOME}/conf/fe.conf"

# need check and create if the log directory existed before outing message to the log file.
if [ ! -d $LOG_DIR ]; then
    mkdir -p $LOG_DIR
fi

# double write log info to file and term
log() {
  echo "$@" >> $LOG_DIR/fe.out
  echo "$@"
}
 
# From 1.2, it must be start FE by non-root.
if [ `whoami` = "root" ];then
  log "[ERROR] You cannot start FE by root, please change user to doris and retry..."
  exit 2
fi

# make sure there are no files of root user in working dir, if not, it perhaps cause some problem...
cd /home/doris
dir_list=($PID_DIR $meta_dir $tmp_dir)
for mydir in ${dir_list[*]}; do
  log "check owner for $mydir ..."
  if [ ! -d ${mydir} ]; then
    log "[WARN] ${mydir} is not exist"
    continue
  fi
  result=$(find ${mydir} -user root)
  if [ $? -ne 0 -o "$result" != "" ]; then
    log "[ERROR] Found some files ownerd by root in ${mydir} ($result)"
    log "Please run command with root user: chown -R doris:doris ${mydir}"
    exit 3
  fi
done

JAVA_HOME=/usr/local/jdk
if [ -z "$JAVA_HOME" ]; then
    JAVA=$(which java)
else
    JAVA="$JAVA_HOME/bin/java"
fi

if [ ! -x "$JAVA" ]; then
    log "The JAVA_HOME environment variable is not defined correctly"
    log "This environment variable is needed to run this program"
    log "NB: JAVA_HOME should point to a JDK not a JRE"
    exit 4
fi

# get jdk version, return version as an Integer.
# 1.8 => 8, 13.0 => 13
jdk_version() {
    local result
    local IFS=$'\n'
    # remove \r for Cygwin
    local lines=$("$JAVA" -Xms32M -Xmx32M -version 2>&1 | tr '\r' '\n')
    for line in $lines; do
        if [[ (-z $result) && ($line = *"version \""*) ]]; then
            local ver=$(echo $line | sed -e 's/.*version "\(.*\)"\(.*\)/\1/; 1q')
            # on macOS, sed doesn't support '?'
            if [[ $ver = "1."* ]]; then
                result=$(echo $ver | sed -e 's/1\.\([0-9]*\)\(.*\)/\1/; 1q')
            else
                result=$(echo $ver | sed -e 's/\([0-9]*\)\(.*\)/\1/; 1q')
            fi
        fi
    done
    log "$result"
}

# check java version and choose correct JAVA_OPTS
java_version=$(jdk_version)
final_java_opt=$JAVA_OPTS
if [ $java_version -gt 8 ]; then
    if [ -z "$JAVA_OPTS_FOR_JDK_9" ]; then
        log "JAVA_OPTS_FOR_JDK_9 is not set in fe.conf"
        exit 5
    fi
    final_java_opt=$JAVA_OPTS_FOR_JDK_9
fi
log "using java version $java_version"
log $final_java_opt

# add libs to CLASSPATH
DORIS_FE_JAR=
for f in $DORIS_HOME/lib/fe/*.jar; do
    if [[ "${f}" == *"doris-fe.jar" ]]; then
        DORIS_FE_JAR="${f}"
        continue
    fi
    CLASSPATH="${f}:${CLASSPATH}"
done

# make sure the doris-fe.jar is at first order, so that some classed
# with same qualified name can be loaded priority from doris-fe.jar
CLASSPATH="${DORIS_FE_JAR}:${CLASSPATH}"
export CLASSPATH="${CLASSPATH}:${DORIS_HOME}/lib:${DORIS_HOME}/conf"

pidfile=$PID_DIR/fe.pid

if [ -f $pidfile ]; then
    if kill -0 $(cat $pidfile) > /dev/null 2>&1; then
        log "Frontend running as process $(cat $pidfile). Stop it first."
        exit 0
    fi
fi

if [ ! -f /bin/limit ]; then
    LIMIT=
else
    LIMIT=/bin/limit
fi

log $(date)

if [ x"$HELPER" != x"" ]; then
    # change it to '-helper' to be compatible with code in Frontend
    HELPER="-helper $HELPER"
fi

if [ ${RUN_DAEMON} -eq 1 ]; then
    nohup $LIMIT $JAVA $final_java_opt -XX:OnOutOfMemoryError="kill -9 %p" org.apache.doris.DorisFE ${HELPER} "$@" >> $LOG_DIR/fe.out 2>&1 < /dev/null &
else
    export DORIS_LOG_TO_STDERR=1
    $LIMIT $JAVA $final_java_opt -XX:OnOutOfMemoryError="kill -9 %p" org.apache.doris.DorisFE ${HELPER} "$@" < /dev/null
fi

echo $! > $pidfile
