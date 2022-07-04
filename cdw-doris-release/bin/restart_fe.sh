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

set -eo pipefail

echo "begin stop FE..."
sh /usr/local/service/doris/bin/stop_fe.sh $@
if [ $? -ne 0 ]; then
  echo "stop FE failed!"
  exit 1
fi
echo "FE stopped successfully!"

sleep 1
echo "begin start FE..."
sh /usr/local/service/doris/bin/start_fe.sh --daemon
if [ $? -ne 0 ]; then
  echo "start FE failed!"
  exit 1
fi
echo "FE started successfully!"
