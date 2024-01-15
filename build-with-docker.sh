#!/bin/bash

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# start docker and pull image
systemctl start docker
docker pull apache/doris:build-env-for-2.0

# clean running docker avoid conflict
docker rm -f $(docker ps -a -q)

# build
docker run -v ${WORK_DIR}/.m2:/root/.m2 -v ${WORK_DIR}/:/root  --name doris-2.x apache/doris:build-env-for-2.0 /bin/bash -c /root/build_all.sh
if [ $? -ne 0 ]; then
  echo "[ERROR] failed to build with docker."
  exit 1
fi
echo "[INFO] success to build with docker."
