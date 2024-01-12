#!/usr/bin/env bash

#set -x

cur_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
work_dir="${cur_dir}/cdw-doris-release"
dest_dir="${work_dir}/doris"

log() {
  echo "$@"
}

# clear old dir list
if [ ! -d "${dest_dir}" ]; then
  log "[INFO] create ${dest_dir}"
  mkdir "${dest_dir}"
else
  log "[INFO] clear the content of ${dest_dir}"
  rm -fr "${dest_dir}/"*
fi

# install fe libs
mkdir -p "${dest_dir}/lib/fe"
ret=$(cp -a "${cur_dir}/output/fe/lib/"*.jar "${dest_dir}/lib/fe/")
if [ $? -ne 0 ]; then
  log "[ERROR] failed to install fe libs."
  exit 1
fi
log "[INFO] success to install fe libs."

# install help-resource 
ret=$(cp -a "${cur_dir}/output/fe/lib/help-resource.zip" "${dest_dir}/lib")
if [ $? -ne 0 ]; then
  log "[ERROR] failed to install help-resource.zip."
  exit 1
fi
log "[INFO] success to install help-resource.zip."

# install be libs
mkdir -p "${dest_dir}/lib/be"
ret=$(cp -a "${cur_dir}/output/be/lib/doris_be" "${dest_dir}/lib/be")
if [ $? -ne 0 ]; then
  log "[ERROR] failed to install doris_be."
  exit 1
fi
log "[INFO] success to install doris_be."

# install hadoop_hdfs and java_extensions
ret=$(cp -a "${cur_dir}/output/be/lib/"{hadoop_hdfs,java_extensions} "${dest_dir}/lib/")
if [ $? -ne 0 ]; then
  log "[ERROR] failed to install hadoop_hdfs and java_extensions."
  exit 1
fi
log "[INFO] success to install hadoop_hdfs and java_extensions."

# install broker libs
mkdir -p "${dest_dir}/lib/broker"
ret=$(cp -a "${cur_dir}/fs_brokers/apache_hdfs_broker/output/apache_hdfs_broker/lib/"*.jar "${dest_dir}/lib/broker")
if [ $? -ne 0 ]; then
  log "[ERROR] failed to install broker."
  exit 1
fi
log "[INFO] success to install broker."

# install tencent libs for broker and fe
ret=$(cp -a "${work_dir}/tencent_libs/"*.jar "${dest_dir}/lib/broker" && 
	cp -a "${work_dir}/tencent_libs/"*.jar "${dest_dir}/lib/fe")
if [ $? -ne 0 ]; then
  log "[ERROR] failed to install tencent libs for broker and fe."
  exit 1
fi
log "[INFO] success to install tencent libs for broker and fe."

# build plugins directory
mkdir -p "${dest_dir}/plugins/AuditLoader"
ret=$(unzip "${cur_dir}/fe_plugins/auditloader/target/auditloader.zip" -d "${dest_dir}/plugins/AuditLoader")
if [ $? -ne 0 ]; then
  log "[ERROR] failed to install audit loader plugin."
  exit 1
fi
log "[INFO] success to install audit loader plugin."

# build other directories
echo "[INFO] deploy udf, spark-dpp, webroot, dict and www"
ret=$(cp -a "${cur_dir}/be/output/udf" "${dest_dir}" &&
cp -a "${cur_dir}/output/fe/spark-dpp" "${dest_dir}" &&
cp -a "${cur_dir}/output/fe/webroot" "${dest_dir}" &&
cp -a "${cur_dir}/output/be/www" "${dest_dir}" &&
cp -a "${cur_dir}/output/be/dict" "${dest_dir}")
if [ $? -ne 0 ]; then
  log "[ERROR] failed to install udf, spark-dpp, webroot, dict and www."
  exit 1
fi
log "[INFO] success to install udf, spark-dpp, webroot, dict and www."

# install conf bin and jdbc drivers.
ret=$(cp -a "${work_dir}/"{conf,bin,jdbc_drivers} "${dest_dir}")
if [ $? -ne 0 ]; then
  log "[ERROR] failed to install conf bin and jdbc drivers."
  exit 1
fi
log "[INFO] success to install conf bin and jdbc drivers."

echo "[INFO] successfully deployed"
