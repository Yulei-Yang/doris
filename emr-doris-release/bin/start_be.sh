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
        echo "Internal error"
        exit 1
        ;;
    esac
done

export DORIS_HOME=$(
    cd "$curdir/.."
    pwd
)
export DORIS_HOME=`cd "$curdir/.."; pwd`

# set odbc conf path
export ODBCSYSINI=$DORIS_HOME/conf

# support utf8 for oracle database
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8

while read line; do
    envline=$(echo $line | sed 's/[[:blank:]]*=[[:blank:]]*/=/g' | sed 's/^[[:blank:]]*//g' | egrep "^[[:upper:]]([[:upper:]]|_|[[:digit:]])*=")
    envline=$(eval "echo $envline")
    if [[ $envline == *"="* ]]; then
        eval 'export "$envline"'
    fi
done < $DORIS_HOME/conf/be.conf

if [ ! -d $LOG_DIR ]; then
    mkdir -p $LOG_DIR
fi

if [ ! -d $UDF_RUNTIME_DIR ]; then
    mkdir -p ${UDF_RUNTIME_DIR}
fi

rm -f ${UDF_RUNTIME_DIR}/*

pidfile=$PID_DIR/be.pid

if [ -f $pidfile ]; then
    if kill -0 $(cat $pidfile) > /dev/null 2>&1; then
        echo "Backend running as process $(cat $pidfile). Stop it first."
        exit 0
    else
        rm $pidfile
    fi
fi

echo "start time: "$(date) >> $LOG_DIR/be.out

if [ ! -f /bin/limit3 ]; then
    LIMIT=
else
    LIMIT="/bin/limit3 -c 0 -n 65536"
fi

ulimit -n 90000

if [ ${RUN_DAEMON} -eq 1 ]; then
    nohup $LIMIT ${DORIS_HOME}/lib/be/doris_be "$@" >> $LOG_DIR/be.out 2>&1 < /dev/null &
else
    export DORIS_LOG_TO_STDERR=1
    $LIMIT ${DORIS_HOME}/lib/be/doris_be "$@" 2>&1 < /dev/null
fi
