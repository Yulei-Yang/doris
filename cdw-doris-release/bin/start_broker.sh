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
    -- "$@")

eval set -- "$OPTS"

RUN_DAEMON=0
while true; do
    case "$1" in
    --daemon)
        RUN_DAEMON=1
        shift
        ;;
    --)
        shift
        break
        ;;
    *)
	echo "Error params for this script!"
        exit 3
        ;;
    esac
done

export BROKER_HOME=$(
    cd "$curdir/.."
    pwd
)

# add libs to CLASSPATH
for f in $BROKER_HOME/lib/broker/*.jar; do
  CLASSPATH=$f:${CLASSPATH};
done
export CLASSPATH=${CLASSPATH}:${BROKER_HOME}/lib:$BROKER_HOME/conf

while read line || [ -n "$line" ]; do
    envline=$(echo $line | sed 's/[[:blank:]]*=[[:blank:]]*/=/g' | sed 's/^[[:blank:]]*//g' | egrep "^[[:upper:]]([[:upper:]]|_|[[:digit:]])*=")
    envline=$(eval "echo $envline")
    if [[ $envline == *"="* ]]; then
        eval 'export "$envline"'
    fi
done < $BROKER_HOME/conf/apache_hdfs_broker.conf

# need check and create if the log directory existed before outing message to the log file.
if [ ! -d $BROKER_LOG_DIR ]; then
    mkdir -p $BROKER_LOG_DIR
fi

# double write log info to file and term
log() {
  echo "$@" >> $BROKER_LOG_DIR/apache_hdfs_broker.out
  echo "$@"
}

# From 1.2, it must be start by non-root.
if [ `whoami` = "root" ];then
  log "[ERROR] You cannot start FE by root, please change user to doris and retry..." 
  exit 2
fi

# make sure there are no files of root user in working dir, if not, it perhaps cause some problem...
cd /home/doris
for mydir in {$PID_DIR}
do
  if [ ! -d ${mydir} ]; then
    log "[WARN] ${mydir} is not exist" 
    continue
  fi
  result=$(find ${mydir} -user root)
  if [ $? -ne 0 -o "$result" != "" ]; then
    log "[ERROR] Found some files ownerd by root in ${mydir} ($result)" 
    log "Please run command with root user: chown -R doris:doris ${mydir}" 
    exit 4
  fi
done
cd -

pidfile=$PID_DIR/apache_hdfs_broker.pid

if [ -f $pidfile ]; then
    if kill -0 $(cat $pidfile) > /dev/null 2>&1; then
        log "Broker running as process $(cat $pidfile).  Stop it first." 
        exit 0
    fi
fi

log `date` 
doris_broker_java_home=/usr/local/jdk
log "the doris broker java home is $doris_broker_java_home" 

if [ "$doris_broker_java_home" = "" ]; then
  log "Error: doris_broker_java_home is not set." 
  exit 4
fi

JAVA=$doris_broker_java_home/bin/java

if [ ${RUN_DAEMON} -eq 1 ]; then
    nohup $LIMIT $JAVA $JAVA_OPTS org.apache.doris.broker.hdfs.BrokerBootstrap "$@" >> $BROKER_LOG_DIR/apache_hdfs_broker.out 2>&1 < /dev/null &
else
    $LIMIT $JAVA $JAVA_OPTS org.apache.doris.broker.hdfs.BrokerBootstrap "$@" >> $BROKER_LOG_DIR/apache_hdfs_broker.out 2>&1 < /dev/null
fi

echo $! > $pidfile
