#!/usr/bin/env bash
set -x

curdir=$(dirname "$0")
curdir=$(
  cd "$curdir"
  pwd
)
HOME_DIR=$curdir

COS_URL="https://derenli-1301087413.cos.ap-guangzhou.myqcloud.com/doris_release_package/thridparty"

rm -fr "${HOME_DIR}/be/src/apache-orc"
rm -fr "${HOME_DIR}/be/src/clucene"

if [[ ! -f "${HOME_DIR}/apache-orc-branch20.tgz" ]]; then
  wget -q "${COS_URL}/apache-orc-branch20.tgz" -P "${HOME_DIR}"
fi

if [[ ! -f "${HOME_DIR}/clucene-branch20.tgz" ]]; then
  wget -q "${COS_URL}/clucene-branch20.tgz" -P "${HOME_DIR}"
fi

tar zxf "${HOME_DIR}/apache-orc-branch20.tgz" -C "${HOME_DIR}/be/src"
tar zxf "${HOME_DIR}/clucene-branch20.tgz" -C "${HOME_DIR}/be/src"

# clean and build all
./build.sh --clean --fe --be --broker --audit --spark-dpp --hive-udf -j90
if [ $? -ne 0 ]; then
  echo "build fe be and ui failed!"
  exit 1
fi

./deploy.sh

