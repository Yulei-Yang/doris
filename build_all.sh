#!/usr/bin/env bash
set -x

HOME_DIR=`pwd`

# clean and build all
./build.sh --clean --fe --be --broker --audit --spark-dpp --hive-udf -j90
if [ $? -ne 0 ]; then
  echo "build fe be and ui failed!"
  exit 1
fi

./deploy.sh

