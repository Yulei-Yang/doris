#!/bin/bash
#set -x

################################################################################################################################
#
# define region: you can change here
#
work_dir_prefix="/data/cdw/upgrade_packages_dir"
cos_bucket_url="https://derenli-bj-1301087413.cos.ap-beijing.myqcloud.com/doris_test"
doris_tar="cdw_doris_v1.1.0.tar.gz"
doris_tar_md5="a5b93ac1876828c99821e2851c03047d"
#
################################################################################################################################

# double write log info to file and term
log() {
  echo "$@" >> ${logFile}
  echo "$@"
}

# rollback new add dirs
rollback_new_add_dirs() {
  if [ ! -f ${newAddDirList} ]; then
    log "[WARN] ${newAddDirList} file is not exist!"
    return 0
  fi

  local new_add_dirs=($(cat ${newAddDirList} | sort -u))
  for new_add_dir in ${new_add_dirs[@]}; do
    if [ -d ${new_add_dir} ]; then
      rm -fr ${new_add_dir}
      log "[INFO] remove dir ${new_add_dir}"
    else
      log "[WARN] ${new_add_dir} is not exist, it maybe run rollback for more times!"
    fi
  done

  log "[INFO] rollback new add dir succuesfullly"
}

# rollback upgrade dirs
rollback_upgrade_dirs() {
  if [ ! -f ${backupUpgradeDirPairList} ]; then
    log "[WARN] ${backupUpgradeDirPairList} file is not exist!"
    return 0
  fi

  local upgrade_dir_pair_list=($(cat ${backupUpgradeDirPairList}))
  for path_pair in ${upgrade_dir_pair_list[@]}; do
    local backup_dir_path=$(echo ${path_pair} | awk -F ',' '{print $1}')
    local upgrade_dir_path=$(echo ${path_pair} | awk -F ',' '{print $2}')

    if [ "${backup_dir_path}" == "" -o "${upgrade_dir_path}" == "" ]; then
      log "[WARN] either backup dir and upgrade dir cannot empty"
      return 0
    fi
    if [ ! -d ${backup_dir_path} ]; then
      log "[WARN] ${backup_dir_path} is not exists!"
      continue
    fi

    if [ -d ${upgrade_dir_path} ]; then
      log "[INFO] ${upgrade_dir_path} is exist, it will be remove!"
      rm -fr "${upgrade_dir_path}"
    fi

    cp -a "${backup_dir_path}" "${upgrade_dir_path}"
    log "[INFO] restore dir from ${backup_dir_path} to ${upgrade_dir_path}"
  done

  log "[INFO] rollback update dir succuesfullly"
}


# rollback automatically when the error occurs in upgrading
error_on_rollback() {
  log "[ERROR] $@" 
  log "[INFO] rollback..." 
  rollback_new_add_dirs
  rollback_upgrade_dirs
}

upgrade_doris() {
  if [ ! -d ${sourceDir} ]; then
    error_on_rollback "${sourceDir} is not exist"
    exit 1
  fi
  local new_version=$(echo $doris_tar | egrep -o "[0-9].[0-9].[0-9]")
  log "[INFO] start to upgrade doris to ${new_version}."

  # download source jar packages
  local source_file=${doris_tar}
  wget -q ${cos_bucket_url}/${source_file} -P ${sourceDir}
  if [ $? -ne 0 ]; then
    error_on_rollback "wget file ${source_file} failed!"
    exit 1
  fi
  log "[INFO] downloaded the doris v${new_version} package."
  #chown hadoop:hadoop -R ${sourceDir}

  # check
  local expected_md5=${doris_tar_md5}
  local upgrade_file_path="${sourceDir}/${source_file}"
  local upgrade_file_md5=$(md5sum ${upgrade_file_path} | awk '{print $1}')
  if [ "${upgrade_file_md5}" != "${expected_md5}" ]; then
    error_on_rollback "$source_file is not ok, md5 not match, expected $expected_md5, actually $upgrade_file_md5(${upgrade_file_path})"
    exit 1
  fi
  log "[INFO] check downloaded doris v${new_version} package ok."

  # untar
  local untar_work_dir="${sourceDir}/"
  tar -zxf "${upgrade_file_path}" -C "${untar_work_dir}"
  if [ $? -ne 0 ]; then
    error_on_rollback "unzip tar package ${upgrade_file_path} failed!"
    exit 1
  fi
  #chown hadoop:hadoop -R "${untar_work_dir}"
  log "[INFO] untar doris v${new_version} package ok."

  # backup old doris
  local dest_dir="/usr/local/service/doris"
  cp -a ${dest_dir} ${backupDir}
  if [ $? -ne 0 ]; then
    error_on_rollback "copy ${dest_dir} to ${backupDir} failed."
    exit 1
  fi
  rm -fr ${dest_dir}
  if [ $? -ne 0 ]; then
    error_on_rollback "remove ${dest_dir} failed."
    exit 1
  fi
  echo "${backupDir}/doris,${dest_dir}" >> ${backupUpgradeDirPairList}
  log "[INFO] backup old doris ok."

  # upgrade
  cp -a "${untar_work_dir}/doris" ${dest_dir}
  echo "${dest_dir}" >> ${newAddDirList}
  log "[INFO] copy ${untar_work_dir}/doris to ${dest_dir} ok."

  # restore conf files
  rm -fr ${dest_dir}/conf
  cp -fr ${backupDir}/doris/conf ${dest_dir}
  rm -fr ${dest_dir}/plugins
  cp -fr ${backupDir}/doris/plugins ${dest_dir}
  log "[INFO] restore old conf and plugins."

  log "[INFO] success to upgrade doris to v${new_version}."
}

usage(){
    echo "USAGE: $0 version"
    echo "or"
    echo "$0 -r version"
    echo " e.g.: \"$0 20201027_v1\" for upgrade"
    echo " or \"$0 -r 20201027_v1\" for rollback to version 20201027_v1"
}

create_log_file() {
  touch ${logFile}
  if [ $? -ne 0 ]; then
    echo "[ERROR] create file ${logFile} failed!"
    exit 1
  fi
}

init() {
  # need a version string as parameter for rollback in future
  if [ $# -ne 1 -a $# -ne 2 ] ; then
    usage $@
    exit 1;
  fi

  if [ $# -eq 2 ]; then
    if [ "$1" != "-r" ]; then
      usage $@
      exit 1;
    fi
  fi

  if [ "$1" == "-r" ]; then
    execute_mode="ROLLBACK"
    upgrade_version_string="$2" 
  else
    execute_mode="UPGRADE"
    upgrade_version_string="$1" 
  fi

  # create source dir and backup dir
  sourceDir="${work_dir_prefix}/${upgrade_version_string}/source"
  backupDir="${work_dir_prefix}/${upgrade_version_string}/backup"
  logFile="${work_dir_prefix}/${upgrade_version_string}/${execute_mode,,}_doris.log"
  backupUpgradeDirPairList="${backupDir}/upgrade_dir_pair_list.txt"
  newAddDirList="${backupDir}/new_add_dir_list.txt"

  # create log file
  if [ -f ${logFile} ]; then
    echo "[ERROR] ${logFile} is exist, maybe you do ${execute_mode,,} more times"
    exit 1
  fi

  # for rollback, all init things done here
  if [ ${execute_mode} == "ROLLBACK" ]; then
    return 0
  fi

  if [ ! -d ${sourceDir} ]; then
    mkdir -p ${sourceDir}
  else
    echo "[ERROR] ${sourceDir} is exist!"
    exit 1
  fi

  if [ ! -d ${backupDir} ]; then
    mkdir -p ${backupDir}
  else
    echo "[ERROR] ${backupDir} is exist!"
    exit 1
  fi

  create_log_file 
}

#########################
# do upgrade or rollback
########################

# init
init $@

# rollback or upgarde
if [ ${execute_mode} == "ROLLBACK" ]; then
  if [ ! -d ${backupDir} ]; then
    echo "[ERROR] backup dir(${backupDir}) must be exist, please check the version number ${upgrade_version_string}"
    exit 1
  fi
  create_log_file 

  # remove new add dirs
  rollback_new_add_dirs

  # restore upgrade dirs
  rollback_upgrade_dirs

  log "[INFO] Rollback successfully!!"

else # for upgarde

  # upgrade 
  upgrade_doris

  log "[INFO] Upgrade successfully!!"
fi
