#!/bin/bash

set -x

doris_tar="cdw_doris_v1.1.0.tar.gz"
bj_upgrade_script_file="upgrade_rollback_doris_to_bj.sh"
gz_upgrade_script_file="upgrade_rollback_doris_to_gz.sh"
prefix="/data/doris-1.x/cdw-doris-release"
pacakge_type="jemalloc_doris"
cos_cmd="/data/coscli-linux"
cos_bj_bucket="cos://derenli-bj-1301087413"
cos_gz_bucket="cos://derenli-1301087413"
workDir="${prefix}/${pacakge_type}"
doris_dir="${workDir}/doris"
doris_tar_path="${workDir}/${doris_tar}"

if [ ! -d "${doris_dir}" ]; then
  log "[INFO] create ${doris_dir}"
  mkdir -p ${doris_dir}
fi

cd ${prefix}
rm -fr ${doris_dir}/*
rm -f "${doris_tar_path}"
mv lib/ plugins/ spark-dpp/ udf/ webroot/ www/ ${workDir}/doris
if [ $? -ne 0 ]; then
  echo "[ERROR] you must compile and deploy in docker first"
  exit 1
fi

cp -fr bin conf ${workDir}/doris
cd ${workDir}
tar zcf ${doris_tar} doris
md5sum_old=$(grep -o "doris_tar_md5=\".*\"" ${workDir}/${bj_upgrade_script_file} | awk -F '=' '{print $2}' | sed 's/\"//g')
md5sum_new=$(md5sum ${doris_tar_path} | awk '{print $1}')
sed -i "s/${md5sum_old}/${md5sum_new}/g" ${workDir}/${bj_upgrade_script_file}
if [ $? -ne 0 ]; then
  echo "[ERROR] replace new md5sum ${md5sum_new} of ${doris_tar_path} to ${workDir}/${bj_upgrade_script_file} failed!"
  exit 1
fi

${cos_cmd} cp ${workDir}/${bj_upgrade_script_file} ${cos_bj_bucket}/${pacakge_type}/${bj_upgrade_script_file}
${cos_cmd} cp ${doris_tar_path} ${cos_bj_bucket}/${pacakge_type}/${doris_tar}

${cos_cmd} cp ${workDir}/${gz_upgrade_script_file} ${cos_gz_bucket}/${pacakge_type}/${gz_upgrade_script_file}
${cos_cmd} cp ${doris_tar_path} ${cos_gz_bucket}/${pacakge_type}/${doris_tar}
