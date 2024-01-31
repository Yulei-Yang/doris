#!/usr/bin/env bash
#set -x

curdir=$(dirname "$0")
curdir=$(
  cd "$curdir"
  pwd
)
WORK_DIR=$curdir

COS_URL="https://derenli-1301087413.cos.ap-guangzhou.myqcloud.com/doris_release_package"

THIRDPARTY_COS_URL="${COS_URL}/thirdparty"
MAVEN_REPO_COS_URL="${COS_URL}/maven_repo"
THIRDPARTY_DIR="${WORK_DIR}/thirdparty"

# update apache-orc
rm -fr "${WORK_DIR}/be/src/apache-orc"
if [[ ! -f "${THIRDPARTY_DIR}/apache-orc-branch20.tgz" ]]; then
  wget -q "${THIRDPARTY_COS_URL}/apache-orc-branch20.tgz" -P "${THIRDPARTY_DIR}"
fi
tar zxf "${THIRDPARTY_DIR}/apache-orc-branch20.tgz" -C "${WORK_DIR}/be/src"

# update CLucece
rm -fr "${WORK_DIR}/be/src/clucene"
if [[ ! -f "${THIRDPARTY_DIR}/clucene-branch20.tgz" ]]; then
  wget -q "${THIRDPARTY_COS_URL}/clucene-branch20.tgz" -P "${THIRDPARTY_DIR}"
fi
tar zxf "${THIRDPARTY_DIR}/clucene-branch20.tgz" -C "${WORK_DIR}/be/src"

# update other thirdparty libs
rm -fr "/var/local/thirdparty/installed"
if [[ ! -f "${THIRDPARTY_DIR}/doris-2.x-thirdparty-libs.tar.gz" ]]; then
  wget -q "${THIRDPARTY_COS_URL}/doris-2.x-thirdparty-libs.tar.gz" -P "${THIRDPARTY_DIR}"
fi
tar zxf "${THIRDPARTY_DIR}/doris-2.x-thirdparty-libs.tar.gz" -C "/var/local/thirdparty"

# download maven repo to speed up for the first time to build
if [[ ! -d "${WORK_DIR}/.m2" ]]; then
  if [[ ! -f "${MAVEN_REPO_COS_URL}/maven_repo_m2_cdwdoris-2.0.tar.gz" ]]; then
    wget -q "${MAVEN_REPO_COS_URL}/maven_repo_m2_cdwdoris-2.0.tar.gz" -P "${WORK_DIR}"
  fi
  tar zxf "${WORK_DIR}/maven_repo_m2_cdwdoris-2.0.tar.gz" -C "${WORK_DIR}"
else 
  prefix="${WORK_DIR}/.m2/repository/org/apache"
  mkdir -p "${prefix}"
  if [[ ! -f "${MAVEN_REPO_COS_URL}/maven_doris-2.0.tar.gz" ]]; then
    wget -q "${MAVEN_REPO_COS_URL}/maven_doris-2.0.tar.gz" -P "${WORK_DIR}"
  fi
  tar zxf "${WORK_DIR}/maven_doris-2.0.tar.gz" -C "${prefix}"
fi

# clean and build all
PARALLEL=$(nproc)
sh ${WORK_DIR}/build.sh --clean --fe --be --broker --audit --spark-dpp --hive-udf -j${PARALLEL}
if [ $? -ne 0 ]; then
  echo "build fe be and ui failed!"
  exit 1
fi

