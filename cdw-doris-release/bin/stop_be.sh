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

curdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

DORIS_HOME="$(
    cd "${curdir}/.."
    pwd
)"
export DORIS_HOME

PID_DIR="$(
    cd "${curdir}"
    pwd
)"
export PID_DIR

while read -r line; do
    envline="$(echo "${line}" |
        sed 's/[[:blank:]]*=[[:blank:]]*/=/g' |
        sed 's/^[[:blank:]]*//g' |
        grep -E "^[[:upper:]]([[:upper:]]|_|[[:digit:]])*=" ||
        true)"
    envline="$(eval "echo ${envline}")"
    if [[ "${envline}" == *"="* ]]; then
        eval 'export "${envline}"'
    fi
done <"${DORIS_HOME}/conf/be.conf"

signum=9
if [[ "$1" = "--grace" ]]; then
    signum=15
fi

pidfile="${PID_DIR}/be.pid"

# get pgrep_pid by pgrep
if command -v pgrep >/dev/null 2>&1; then
    pgrep_pid="$(pgrep -u doris -x doris_be -n)"
    if [[ -z "${pgrep_pid}" ]]; then
        echo "failed to get pid of doris_be by pgrep."
    fi
else
    echo "pgrep command is not available on this system."
fi

if [[ -f "${pidfile}" ]]; then
    pid="$(cat "${pidfile}")"
    pidfile_pid=${pid};
else
    echo "The pid file is not exist."
fi

# check if pid valid
if test -z "${pid}"; then
    if [[ -z "${pgrep_pid}" ]]; then
        echo "Both the pid of pid file and pgrep pid are invalid pid, maybe doris_be not alive."
        exit 0
    else
        echo "The pid of pid file is invalid, using pgrep pid to continue..."
        pid=${pgrep_pid};
    fi
fi

# The function to 
function need_use_pprep_pid() {
    if [[ -z "${pgrep_pid}" ]]; then
       return 1 # false 
    fi
    if [[ "${pid}" == "${pgrep_pid}" ]]; then
       return 1 # false 
    fi
    return 0 # true
}

# check if pid process exist
if ! kill -0 "${pid}" 2>&1; then
    echo "The pid of pid file ${pid} is not a valid process."
    if need_use_pprep_pid; then
        echo "Using pgrep pid to continue..."
        if ! kill -0 "${pgrep_pid}" 2>&1; then
            echo "ERROR: Either be process ${pid} nor ${pgrep_pid} does exist."
            exit 1
        fi
        pid=${pgrep_pid};
    else
        echo "ERROR: be process ${pid} does not exist."
        exit 2
    fi
fi

pidcomm="$(basename "$(ps -p "${pid}" -o comm=)")"
# check if pid process is backend process
if [[ "doris_be" != "${pidcomm}" ]]; then
    echo "The pid of pid file indicated process may not be Doris BE. "
    if need_use_pprep_pid; then
        echo "Using pgrep pid to continue..."
        pidcomm="$(basename "$(ps -p "${pgrep_pid}" -o comm=)")"
        if [[ "doris_be" != "${pidcomm}" ]]; then
            echo "ERROR: pid process may not be Doris BE. "
            exit 3
        fi
	pid=${pgrep_pid};
    else
        echo "ERROR: pid process may not be Doris BE. "
        exit 4
    fi
fi

# kill pid process and check it
if kill "-${signum}" "${pid}" >/dev/null 2>&1; then
    while true; do
        if kill -0 "${pid}" >/dev/null 2>&1; then
            echo "waiting be to stop, pid: ${pid}"
            sleep 2
        else
            echo "stop ${pidcomm}, and remove pid file. "
            if [[ -f "${pidfile}" ]]; then rm "${pidfile}"; fi
            exit 0
        fi
    done
else
    echo "ERROR: failed to stop ${pidfile_pid} from pid file and pgrep pid $pgrep_pid"
    exit 5
fi
