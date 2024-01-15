#!/usr/bin/env bash

#set -x

cur_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
work_dir="${cur_dir}/cdw-doris-release"
doris_dir_name="doris"
dest_dir="${work_dir}/${doris_dir_name}"

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

# Package(1/4) get version string
version_file="${cur_dir}/version.txt"
if [[ ! -f ${version_file} ]]; then
  log "[ERROR] failed to find version.txt in ${cur_dir}"
  exit 1
fi
version_str=$(cat ${version_file})
cp -f "${version_file}" "${dest_dir}"
log "[INFO] success to get version string is ${version_str}."

# Package(2/4) package the tar without strip
doris_be_without_strip_tar="${version_str}-doris_be.tar.gz"
cd "${dest_dir}/lib/be"
tar -zcf "${doris_be_without_strip_tar}" "doris_be"
if [ $? -ne 0 ]; then
  log "[ERROR] compress tar package ${doris_be_without_strip_tar_path} failed!"
  exit 1
fi
mv "${doris_be_without_strip_tar}" "${work_dir}"
if [ $? -ne 0 ]; then
  log "[ERROR] move tar package ${doris_be_without_strip_tar} to ${work_dir} failed!"
  exit 1
fi
log "[INFO] success to compress doris_be without strip to ${work_dir}/${doris_be_without_strip_tar}."

# Package(3/4) strip doris_be
doris_be_without_strip="${dest_dir}/lib/be/doris_be"
if [ ! -f "${doris_be_without_strip}" ]; then
  log "[ERROR] ${doris_be_without_strip} not found"
  exit -1
fi
strip --strip-debug ${doris_be_without_strip}
if [ $? -ne 0 ]; then
  log "[ERROR] strip ${doris_be_without_strip} failed!"
  exit 1
fi
log "[INFO] success to strip ${doris_be_without_strip}."

# Package(3/4) make tar package
doris_tar="${version_str}.tar.gz"
log "[INFO] start to make ${doris_tar} for ${dest_dir}, it need to a few minutes..."
cd ${work_dir}
rm -f ${doris_tar}
tar -zcf "${doris_tar}" "${doris_dir_name}"
if [ $? -ne 0 ]; then
  log "[ERROR] compress tar package ${doris_tar} failed!"
  exit 1
fi
log "[INFO] success to make new tar package ${work_dir}/${doris_tar}."

echo "[INFO] successfully deployed"
