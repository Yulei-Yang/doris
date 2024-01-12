#!/bin/bash

#set -x

################################################################################################################################
#
# define region: you can change here
#
doris_dir_name="doris"
coscli_cmd="/data/coscli-linux"
cos_backup_subdir="cdw_doris_backup"
log_file="log_package_and_deploy_to_cos.log"
cos_bucket="cos://derenli-1301087413" 
doris_release_package_dir="doris_release_package"
doris_be_debug_package_dir="doris_be_debug_package"
upgrade_script_file="upgrade_doris_from_cos.sh"
#release_to_chongqing_cos_url="https://cdwch-cos-apps-cq-1305504398.cos.ap-chongqing.myqcloud.com/doris/1.2.0"
#
################################################################################################################################

curdir=$(dirname "$0")
curdir=$(
  cd "$curdir"
  pwd
)
workDir=$curdir
logFile=${workDir}/${log_file}

log() {
  echo "$@" >> ${logFile}
  echo "$@"
}

jdk_version() {
  local java_cmd="${1}"
  local result
  local IFS=$'\n'

  if [[ -z "${java_cmd}" ]]; then
    result=no_java
    return 1
  else
    local version
    # remove \r for Cygwin
    version="$("${java_cmd}" -Xms32M -Xmx32M -version 2>&1 | tr '\r' '\n' | grep version | awk '{print $3}')"
    version="${version//\"/}"
    if [[ "${version}" =~ ^1\. ]]; then
      result="$(echo "${version}" | awk -F '.' '{print $2}')"
    else
      result="$(echo "${version}" | awk -F '.' '{print $1}')"
    fi
  fi
  echo "${result}"
  return 0
}

setup_java_env() {
  local java_version

  if [[ -z "${JAVA_HOME}" ]]; then
    JAVA_HOME=$(dirname $(dirname $(readlink -f $(which javac))))
    if [ ! -f "${JAVA_HOME}/bin/java" ]; then
      log "[ERROR] JAVA_HOME is not set and java not found"
      exit -1
    fi
    log "[WARN] JAVA_HOME not set, set to ${JAVA_HOME}"
  fi

  local jvm_arch='amd64'
  if [[ "$(uname -m)" == 'aarch64' ]]; then
    jvm_arch='aarch64'
  fi
  java_version="$(
    set -e
    jdk_version "${JAVA_HOME}/bin/java"
  )"
  if [[ "${java_version}" -gt 8 ]]; then
    export LD_LIBRARY_PATH="${JAVA_HOME}/lib/server:${JAVA_HOME}/lib:${LD_LIBRARY_PATH}"
    # JAVA_HOME is jdk
  elif [[ -d "${JAVA_HOME}/jre" ]]; then
    export LD_LIBRARY_PATH="${JAVA_HOME}/jre/lib/${jvm_arch}/server:${JAVA_HOME}/jre/lib/${jvm_arch}:${LD_LIBRARY_PATH}"
    # JAVA_HOME is jre
  else
    export LD_LIBRARY_PATH="${JAVA_HOME}/lib/${jvm_arch}/server:${JAVA_HOME}/lib/${jvm_arch}:${LD_LIBRARY_PATH}"
  fi
}


usage(){
    echo "USAGE: $0 [-t|test]"
    echo " e.g.: \"$0 test \" for testing"
}


init() {

  if [ ! -d "${workDir}/lib" ]; then
    log "[ERROR] Meeting an error, make sure to run deploy.sh in docker firstly to deploy lib to ${workDir}."
    exit -1
  fi

  if [ $# -ne 0 -a $# -ne 1 ] ; then
    usage $@
    exit 1;
  fi

  # prepare jvm if needed
  setup_java_env || true
  
  #export LD_LIBRARY_PATH=/usr/lib/jvm/java-8/jre/lib/amd64/server/
  local doris_be_bin="${workDir}/../be/output/lib/doris_be"
  if [ ! -f ${doris_be_bin} ]; then
    log "[ERROR] ${doris_be_bin} not exists."
    exit -1
  fi
  
  local version_str=$(${doris_be_bin} --version)
  local version=$(echo ${version_str} | egrep -o "[1|2]\.[0-9]" | head -n 1)
  if [ "$version" != "1.1" -a "$version" != "1.2" -a "$version" != "2.0" ]; then
    log "[ERROR] Get doris version failed, please make sure ${doris_be_bin} is executable."
    exit -1
  fi

  # now init global variables
  local short_version=$(git log -1 --pretty=format:"%h")
  local doris_full_version="${version_str%%(*}-${short_version:0:7}"
  doris_version_string=${version_str/(/-${short_version:0:7}(}
  doris_tar="${doris_full_version}.tar.gz"
  doris_tar_sha="${doris_tar}.sha512"
  doris_be_without_strip_tar="${doris_full_version}-doris_be.tar.gz"
  doris_tar_sha_file_path="${workDir}/${doris_tar_sha}"

  log "[INFO] doris version is ${doris_full_version}"
  log "[INFO] doris tar package is ${doris_tar}"
  log "[INFO] sha512 file for doris tar package is ${doris_tar_sha}"
  log "[INFO] upgrade script file for doris is ${upgrade_script_file}"
  log "[INFO] cos bucket is ${cos_bucket}"
}

package_and_deploy_to_cos() {
  log "[INFO] start to deploy to cos."

  # clear old dir and package
  local dest_dir="${workDir}/${doris_dir_name}"
  local upgrade_file_path="${workDir}/${doris_tar}"
  rm -f ${upgrade_file_path}
  log "[INFO] clear old package(${upgrade_file_path})."

  # package debug version
  local doris_be_without_strip="${dest_dir}/lib/be/doris_be"
  if [ ! -f "${doris_be_without_strip}" ]; then
    log "[ERROR] ${doris_be_without_strip} not found"
    exit -1
  fi
  cd "${dest_dir}/lib/be"
  tar -zcf "${doris_be_without_strip_tar}" "doris_be"
  if [ $? -ne 0 ]; then
    log "[ERROR] compress tar package ${doris_be_without_strip_tar_path} failed!"
    exit 1
  fi
  mv "${doris_be_without_strip_tar}" ${workDir}
  cd ${workDir}
  local doris_be_without_strip_tar_path="${workDir}/${doris_be_without_strip_tar}"
  log "[INFO] compress tar package ${doris_be_without_strip_tar} ok."

  # strip doris_be
  strip --strip-debug ${doris_be_without_strip}
  if [ $? -ne 0 ]; then
    log "[ERROR] strip ${doris_be_without_strip} failed!"
    exit 1
  fi
  log "[INFO] strip ${doris_be_without_strip} ok!"

  # make tar package
  log "[INFO] start to make a tar package ${upgrade_file_path} from ${doris_dir_name}, it need to a few minutes..."
  cd ${workDir}
  rm -f ${upgrade_file_path}
  if [ ! -d ${doris_dir_name} ]; then
    log "[ERROR] ${doris_dir_name} is not exist!"
    exit 1
  fi
  tar -zcf "${upgrade_file_path}" "${doris_dir_name}"
  if [ $? -ne 0 ]; then
    log "[ERROR] compress tar package ${upgrade_file_path} failed!"
    exit 1
  fi
  log "[INFO] make new tar package ${upgrade_file_path} ok."

  # generate sha512sum check file
  cd ${workDir}
  sha512sum ${doris_tar} > ${doris_tar_sha_file_path}
  if [ $? -ne 0 ]; then
    log "[ERROR] generate sha512 checksum file ${doris_tar_sha_file_path} for ${upgrade_file_path} failed!"
    exit 1
  fi

  # upload to cos
  log "[INFO] start to upload the tar package ${upgrade_file_path} to cos bucket, it need to a few minutes..."
  if [ -e ${coscli_cmd} ]; then

    local cos_bucket_url="${cos_bucket}/${doris_release_package_dir}"
    
    # backup last tar package, it will cover old one
    ${coscli_cmd} cp "${cos_bucket_url}/${doris_tar}" "${cos_bucket_url}/${cos_backup_subdir}/${doris_tar}"
    if [ $? -ne 0 ]; then
      log "[WARN] backup ${doris_tar} to ${cos_bucket_url}/${cos_backup_subdir} failed! Maybe old one is not exist."
    else
      log "[INFO] backup ${doris_tar} to ${cos_bucket_url}/${cos_backup_subdir} ok!"
    fi

    # upload tar package
    ${coscli_cmd} cp ${upgrade_file_path} ${cos_bucket_url}/${doris_tar}
    if [ $? -ne 0 ]; then
      log "[ERROR] upload ${upgrade_file_path} to ${cos_bucket_url}/${doris_tar} failed!"
      exit 1
    fi

    # upload upgrade script 
    ${coscli_cmd} cp ${workDir}/${upgrade_script_file} ${cos_bucket_url}/${upgrade_script_file}
    if [ $? -ne 0 ]; then
      log "[ERROR] upload ${workDir}/${upgrade_script_file} to ${cos_bucket_url}/${upgrade_script_file} failed!"
      exit 1
    fi

    # backup sha512 check sum file
    ${coscli_cmd} cp "${cos_bucket_url}/${doris_tar_sha}" "${cos_bucket_url}/${cos_backup_subdir}/${doris_tar_sha}"
    if [ $? -ne 0 ]; then
      log "[WARN] backup ${doris_tar_sha} to ${cos_bucket_url}/${cos_backup_subdir} failed! Maybe old one is not exist."
    else
      log "[INFO] backup ${doris_tar_sha} to ${cos_bucket_url}/${cos_backup_subdir} ok!"
    fi

    # upload sha512 check sum file
    ${coscli_cmd} cp ${doris_tar_sha_file_path} ${cos_bucket_url}/${doris_tar_sha}
    if [ $? -ne 0 ]; then
      log "[ERROR] upload ${doris_tar_sha_file_path} to ${cos_bucket_url}/${doris_tar_sha} failed!"
      exit 1
    fi
    log "[INFO] upload (${upgrade_script_file}), tar package(${upgrade_file_path}) and checksum file(${doris_tar_sha_file_path}) to ${cos_bucket_url} ok"

    # upload doris_be without strip tar file
    cos_bucket_url="${cos_bucket}/${doris_be_debug_package_dir}"
    ${coscli_cmd} cp ${doris_be_without_strip_tar_path} ${cos_bucket_url}/${doris_be_without_strip_tar}
    if [ $? -ne 0 ]; then
      log "[ERROR] upload ${doris_be_without_strip_tar_path} to ${cos_bucket_url}/${doris_be_without_strip_tar} failed!"
      exit 1
    fi
    log "[INFO] upload ${doris_be_without_strip_tar_path} to ${cos_bucket_url} ok"
  fi

#  log "[INFO] upload to chongqing cos"
#  curl -T ${doris_tar} ${release_to_chongqing_cos_url}/${doris_tar}

  log "[INFO] success to release doris"
}

show_release_info() {
  echo ""
  echo "****************** release infomation ******************"
  echo ${doris_version_string} | sed 's/(build.*) /\n/g'
  cd ${workDir}
  md5sum "${doris_tar}"
  md5sum "doris/lib/be/doris_be"
  md5sum "doris/lib/fe/doris-fe.jar"

  local str=$(cat ${workDir}/${doris_tar_sha})
  local len=${#str}
  local max_len=60
  local strtail=$((len%${max_len}))
  local line=$((len/${max_len}))  
  local sPos=0 
  for ((n=1;n<=$line;n++))
  do
    echo ${str:sPos:${max_len}}
    sPos=$((sPos+${max_len}))
  done
  if [ $strtail -ne 0 ]; then
    echo ${str:sPos:strtail}
  fi
  echo "********************************************************"
  echo ""
}

show_git_log_message() {
  SKIP_LINE_NUM=0
  git log -5 --skip=$SKIP_LINE_NUM --date=format:'[%Y-%m-%d %H:%M:%S]' --pretty=format:"%ad [%an] %s"
  echo "..."
  SKIP_LINE_NUM=$(git log --oneline | egrep -c -w "^[^[:space:]]+\s+\[Tencent\]")
  git log -5 --skip=$SKIP_LINE_NUM --date=format:'[%Y-%m-%d %H:%M:%S]' --pretty=format:"%ad [%an] %s"
}

init $@
package_and_deploy_to_cos
show_release_info || true
show_git_log_message || true
