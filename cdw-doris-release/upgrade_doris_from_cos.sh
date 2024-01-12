#!/bin/bash
#set -x

################################################################################################################################
#
# define region: you can change here
#
work_dir_prefix="/data/cdw/upgrade_packages_dir"
bj_cos_bucket_url="https://cdwch-cos-apps-bj-1305504398.cos.ap-beijing.myqcloud.com"
gz_cos_bucket_url="https://cdwch-cos-apps-gz-1305504398.cos.ap-guangzhou.myqcloud.com"
sh_cos_bucket_url="https://cdwch-cos-apps-sh-1305504398.cos.ap-shanghai.myqcloud.com"
nj_cos_bucket_url="https://cdwch-cos-apps-nj-1305504398.cos.ap-nanjing.myqcloud.com"
hk_cos_bucket_url="https://cdwch-cos-apps-hk-1305504398.cos.ap-hongkong.myqcloud.com"
cq_cos_bucket_url="https://cdwch-cos-apps-cq-1305504398.cos.ap-chongqing.myqcloud.com"
sg_cos_bucket_url="https://cdwch-cos-apps-sp-1305504398.cos.ap-singapore.myqcloud.com"
cd_cos_bucket_url="https://cdwch-cos-apps-cd-1305504398.cos.ap-chengdu.myqcloud.com"
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

# just for those upgarding from 1.1 to 1.2 and need to swith user from root to doris
monitor_json_fe_doris=$(cat <<- 'EOF'
[{"processName":"org.apache.doris.PaloFe","startCmd":{"cmd":"sh","timeout":3600,"arguments":["/usr/local/service/doris/bin/start_fe.sh","--daemon"],"environments":null},"user":"doris","group":"doris","port":""},{"processName":"org.apache.doris.broker.hdfs.BrokerBootstrap","startCmd":{"cmd":"sh","timeout":3600,"arguments":["/usr/local/service/doris/bin/start_broker.sh","--daemon"],"environments":null},"user":"doris","group":"doris","port":""}]
EOF
)

monitor_json_be_doris=$(cat <<- 'EOF'
[{"processName":"doris_be","startCmd":{"cmd":"sh","timeout":3600,"arguments":["/usr/local/service/doris/bin/start_be.sh","--daemon"],"environments":null},"user":"doris","group":"doris","port":""},{"processName":"org.apache.doris.broker.hdfs.BrokerBootstrap","startCmd":{"cmd":"sh","timeout":3600,"arguments":["/usr/local/service/doris/bin/start_broker.sh","--daemon"],"environments":null},"user":"doris","group":"doris","port":""}]
EOF
)
update_monitor_json() {
  local monitor_json="/usr/local/service/cdwch/monitor.json"
  local monitor_json_bak="${monitor_json}.bak"
  local monitor_json_old="${monitor_json}.old"

  local need_to_fix=true
  local node_type=""
  if [ -f ${monitor_json} ]; then
    local actual_json=`echo $(cat ${monitor_json})`
    cat ${monitor_json} | grep start_be > /dev/null
    if [ $? -eq 0 ]; then # for BE
      node_type="BE"
      if [ "${monitor_json_be_doris}" == "${actual_json}" ]; then
        need_to_fix=false
      fi
    fi
      
    cat ${monitor_json} | grep PaloFe > /dev/null
    if [ $? -eq 0 ]; then
      if [ "${node_type}" == "BE" ]; then
        log "[WARN] there are some errors in ${monitor_json}($(cat ${monitor_json}))"
        return 1
      fi
      node_type="FE"
      if [ "${monitor_json_fe_doris}" == "${actual_json}" ]; then
        need_to_fix=false
      fi
    fi
  fi
  if [ "${need_to_fix}" = false ]; then
    log "[INFO] no need to fix monitor.json"
    return 0
  fi

  # check and make sure monitor bak file exist
  if [ ! -f ${monitor_json_bak} ]; then
    if [ ! -f ${monitor_json} ]; then
      log "[WARN] Update monitor json failed (Both ${monitor_json} and ${monitor_json_bak} are not exist!)"
      return 1
    fi
    mv ${monitor_json} ${monitor_json_bak}
    if [ $? -ne 0 ]; then
      log "[WARN] Update monitor json failed (move ${monitor_json} to ${monitor_json_bak} failed!)"
      return 1
    fi
    log "[INFO] move ${monitor_json} to ${monitor_json_bak}"
  fi

  # backup old monitor
  mv ${monitor_json_bak} ${monitor_json_old}
  if [ $? -ne 0 ]; then
    log "[WARN] Update monitor json failed (Move ${monitor_json_bak} to ${monitor_json_old} failed!)"
    return 1
  fi
  log "[INFO] move ${monitor_json_bak} to ${monitor_json_old}"

  # create new monitor files according to old
  cat ${monitor_json_old} | grep start_be > /dev/null
  if [ $? -eq 0 ]; then
    echo ${monitor_json_be_doris} > ${monitor_json_bak}
    if [ $? -ne 0 ]; then
      log "[WARN] Create monitor json failed!"
      return 1
    fi
    if [ "${node_type}" == "FE" ]; then
      log "[WARN] there are some errors in ${monitor_json_old}($(cat ${monitor_json_old}))"
      return 1
    fi
    node_type="BE"
    log "[INFO] create new ${monitor_json_bak} for ${node_type} node"
  else 
    cat ${monitor_json_old} | grep PaloFe > /dev/null
    if [ $? -eq 0 ]; then
      echo ${monitor_json_fe_doris} > ${monitor_json_bak}
      if [ "${node_type}" == "BE" ]; then
        log "[WARN] there are some errors in ${monitor_json_old}($(cat ${monitor_json_old}))"
        return 1
      fi
      node_type="FE"
      log "[INFO] create new ${monitor_json_bak} for ${node_type} node"
    else
      log "[WARN] there are some errors in ${monitor_json_old}($(cat ${monitor_json_old}))"
      log "[WARN] create new ${monitor_json_bak} failed!"
      return 1
    fi
  fi
  
  if [ "$1" == "RESTORE" ]; then
    cp -f ${monitor_json_bak} ${monitor_json} 
    if [ $? -ne 0 ]; then
      log "[WARN] Restore monitor json failed (cp -f ${monitor_json_bak} to ${monitor_json} failed!)"
      return 1
    fi
    log "[INFO] restore ${monitor_json_bak} to ${monitor_json}"
  fi
}

update_agent() {
  local agent_dir="/usr/local/service/cdwch/cdwch-agent"
  if [ -d ${agent_dir} ]; then
    local agent_file="${agent_dir}/bin/cdwch-agent"
    if [ -f ${agent_file} ]; then
      local latest_md5="1d80be0c4e48adb23682a57844706288"
      local current_md5=$(md5sum ${agent_file} | awk '{print $1}')
      if [ $? -eq 0 ] && [ "${current_md5}" == "${latest_md5}" ]; then
        log "[INFO] current ${agent_file} is the same as the latest one."
        log "[INFO] no need to fix cdwch-agent"
        return 0
      else
        log "[INFO] current ${agent_file} is old(md5sum is ${current_md5}), need to update..."
      fi
    fi
    rm -fr ${agent_dir}
    log "[INFO] remove dir ${agent_dir}"
  else
    log "[WARN] ${agent_dir} is not exist!"
  fi

  # remove tar package of old agent
  local agent_tar="/usr/local/service/cdwch/cdwdoris-agent-1.0.0.tar.gz"
  if [ -f ${agent_tar} ]; then
    rm -f ${agent_tar}
    log "[INFO] remove file ${agent_tar}"
  else
    log "[WARN] ${agent_tar} is not exist!"
  fi

  # kill cdwch-agent for starting new version
  pkill -9 cdwch-agent
  if [ $? -ne 0 ]; then
    log "[WARN] kill cdwch-agent process failed!"
  else
    log "[INFO] killed cdwdoris-agent process and it will start automaticlly."
  fi
}

change_working_dir_owner() {
  local need_to_fix=false
  local fe_dir="/data/cdw/doris/fe"
  local be_dir="/data/cdw/doris/be"
  local broker_dir="/data/cdw/doris/broker"
  local work_dir="/usr/local/service/doris"
#  local dir_list=(${fe_dir}/pid ${be_dir}/pid ${broker_dir}/pid ${fe_dir}/meta ${fe_dir}/temp_dir 
#                  ${be_dir}/storage ${be_dir}/lib/small_file ${be_dir}/var/pull_load
#                  ${fe_dir}/log ${be_dir}/log ${broker_dir}/log)
###################################################################
# Here check and change high level than start script do, 
# because sometime perhaps we create new file ownered by 
# root exceptionly in these dir, that should not stoping starting.
###################################################################
  local dir_list=(${fe_dir} ${be_dir} ${broker_dir} ${work_dir})
  for mydir in ${dir_list[*]}; do
    if [ ! -d ${mydir} ]; then
      log "[INFO] ${mydir} is not exist!" 
      continue
    fi
    local result=$(find ${mydir} -user root)
    if [ $? -ne 0 -o "$result" != "" ]; then
      log "[WARN] ${mydir} is ownered by root, now change to doris"
      need_to_fix=true
      chown -R doris:doris ${mydir}
      if [ $? -ne 0 ]; then
        error_on_rollback "[FATAL] change the owner of ${mydir} to doris:doris failed"
        exit 1
      fi
    else
      log "[INFO] check ${mydir} is OK."
    fi
  done
  if [ "${need_to_fix}" = false ]; then
    log "[INFO] no working dir are belong to root"
  fi
}

upgrade_doris() {
  if [ ! -d ${sourceDir} ]; then
    error_on_rollback "${sourceDir} is not exist"
    exit 1
  fi

  local new_version=$(echo $doris_tar | egrep -o "[0-9]\.[0-9]+" | head -1)
  log "[INFO] start to upgrade doris to ${new_version} ($doris_tar)."

  # decide the dir according to new version
  local cos_subdir=""
  case ${new_version} in
    0.15)
        cos_subdir="0.15.0"
        ;;
    1.0)
        cos_subdir="1.0.1"
        ;;
    1.1)
        cos_subdir="1.1.0"
        ;;
    1.2)
        cos_subdir="1.2.0"
        ;;
    2.0)
        cos_subdir="2.0"
        ;;
    *)
        error_on_rollback "Cannot figure out the cos subdir for unknown ${new_version}!"
        exit 1
        ;;
  esac
  cos_subdir="doris/${cos_subdir}"

  # download source packages
  local source_file=${doris_tar}
  if [ -f ${sourceDir}/${source_file} ]; then
    error_on_rollback "The target file ${source_file} is already exists in ${sourceDir}, upgrade failed!"
    exit 1
  fi

  if [ -f "/data/${source_file}" ]; then
    log "[INFO] ${source_file} is exists in dir /data, move to ${sourceDir}/${source_file}..."
    mv "/data/${source_file}" "${sourceDir}/${source_file}"
    if [ $? -ne 0 ]; then
      error_on_rollback "move file ${source_file} from /data to ${sourceDir} failed!"
      exit 1
    fi
  else
    log "[INFO] ${source_file} is not exists in dir /data, it will start to wget from cos..."
    log "And the url is ${cos_bucket_url}/${cos_subdir}/${source_file}"
    wget -q ${cos_bucket_url}/${cos_subdir}/${source_file} -P ${sourceDir}
    if [ $? -ne 0 ]; then
      error_on_rollback "wget file ${source_file} failed!"
      exit 1
    fi
    log "[INFO] downloaded the doris ${source_file} package."
  fi

  # untar
  log "[INFO] start to untar doris package ..."
  local untar_work_dir="${sourceDir}/"
  local upgrade_file_path="${sourceDir}/${source_file}"
  tar -zxf "${upgrade_file_path}" -C "${untar_work_dir}"
  if [ $? -ne 0 ]; then
    error_on_rollback "unzip tar package ${upgrade_file_path} failed!"
    exit 1
  fi
  log "[INFO] untar doris v${new_version} package ok."

  # get old version
  local dest_dir="/usr/local/service/doris"
  local doris_be_bin="${dest_dir}/lib/be/doris_be"
  if [ ! -f ${doris_be_bin} ]; then
    log "[INFO] doris_be is not exists, try to find palo_be in ${dest_dir}/lib/be."
    doris_be_bin="${dest_dir}/lib/be/palo_be"
    if [ ! -f ${doris_be_bin} ]; then
      error_on_rollback "Both doris_be and palo_be are not exists."
      exit -1
    fi
  fi
  local version_str=$(${doris_be_bin} --version)
  local old_version=$(echo ${version_str} | egrep -o "[0-9]\.[0-9]+" | head -1)
  log "[INFO] Found your old version string of Doris is ${version_str}"

  # backup old doris
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
  log "[INFO] restore old conf of BE and FE."
  rm -fr ${dest_dir}/conf
  cp -a ${backupDir}/doris/conf ${dest_dir}
  log "[INFO] restore old conf of audit loader plugin."
  cp -f "${backupDir}/doris/plugins/AuditLoader/plugin.conf" "${dest_dir}/plugins/AuditLoader"

  # restore keytab file if exists
  if ls ${backupDir}/doris/*.keytab &> /dev/null; then
    log "[INFO] restore keytab files to ${dest_dir}."
    cp -f ${backupDir}/doris/*.keytab ${dest_dir}
  fi

  # restore old jdbc drivers
  local old_jdbc_driver_dir="${backupDir}/doris/jdbc_drivers"
  local new_jdbc_driver_dir="${dest_dir}/jdbc_drivers"
  if [ -d "${old_jdbc_driver_dir}" ]; then
    log "[INFO] restore old jdbc_drivers."
    if [ ! -d "${new_jdbc_driver_dir}" ]; then
      mkdir -p ${new_jdbc_driver_dir}
    fi
    cp -f ${old_jdbc_driver_dir}/*.jar "${new_jdbc_driver_dir}"
  fi

  # restore scripts for cloud manage controller 
  local new_scirpts_dir="${dest_dir}/bin"
  local apiserver_operation_sh="${backupDir}/doris/bin/apiserver_operation.sh"
  if [ -f "${apiserver_operation_sh}" ]; then
    log "[INFO] restore ${apiserver_operation_sh}."
    cp -f "${apiserver_operation_sh}" "${new_scirpts_dir}"
  fi
  local fe_monitor_sh="${backupDir}/doris/bin/fe_monitor.sh"
  if [ -f "${fe_monitor_sh}" ]; then
    log "[INFO] restore ${fe_monitor_sh}."
    cp -f "${fe_monitor_sh}" "${new_scirpts_dir}"
  fi

  # need to add doris user group for upgrading from 1.2 and later
  if [ "${new_version}" == "1.2" ] && [ "${old_version}" == "1.1" ]; then

    log "[INFO] Due to upgrading from ${old_version} to ${new_version}, need to change user from root to doris for starting doris...."

    local group="doris"
    local user="doris"

    # 1. create group if not exists
    egrep "^$group" /etc/group >& /dev/null
    if [ $? -ne 0 ]; then
      groupadd $group
      if [ $? -ne 0 ]; then
        log "[WARN] add group $group failed"
      else
        log "[INFO] Add group $group successfully!"
      fi
    fi

    # 2. create user if not exists
    egrep "^$user" /etc/passwd >& /dev/null
    if [ $? -ne 0 ]; then
      useradd -g $group $user
      if [ $? -ne 0 ]; then
        log "[WARN] add user $user to $group failed"
      else
        log "[INFO] Add user $user successfully!"
      fi
    fi

    # 3. check and fix owners of working dir
    log "[INFO] check and fix owners of working dir"
    change_working_dir_owner
    
    # 4. check and fix monitor.json
    log "[INFO] check and fix monitor.json"
    update_monitor_json

    # 5. check and fix cdwch-agent
    log "[INFO] check and fix cdwch-agent"
    update_agent
  fi

  log "[INFO] success to upgrade doris from v${old_version} to v${new_version}."
}

fix_start_scripts() {
  # download source packages
  local cos_subdir="doris/1.2.0"
  local dest_dir="/usr/local/service"
  local source_file=${doris_tar}
  if [ -f ${sourceDir}/${source_file} ]; then
    error_on_rollback "The target file ${source_file} is already exists in ${sourceDir}, check and fix done?"
    exit 1
  fi

  if [ -f "/data/${source_file}" ]; then
    log "[INFO] ${source_file} is exists in dir /data, move to ${sourceDir}/${source_file}..."
    mv "/data/${source_file}" "${sourceDir}/${source_file}"
    if [ $? -ne 0 ]; then
      error_on_rollback "move file ${source_file} from /data to ${sourceDir} failed!"
      exit 1
    fi
  else
    log "[INFO] ${source_file} is not exists in dir /data, it will start to wget from cos..."
    log "And the url is ${cos_bucket_url}/${cos_subdir}/${source_file}"
    wget -q ${cos_bucket_url}/${cos_subdir}/${source_file} -P ${sourceDir}
    if [ $? -ne 0 ]; then
      error_on_rollback "wget file ${source_file} failed!"
      exit 1
    fi
    log "[INFO] downloaded the doris ${source_file} package."
  fi

  # untar
  log "[INFO] start to untar doris package ..."
  local untar_work_dir="${sourceDir}/"
  local upgrade_file_path="${sourceDir}/${source_file}"
  tar -zxf "${upgrade_file_path}" -C "${untar_work_dir}"
  if [ $? -ne 0 ]; then
    error_on_rollback "unzip tar package ${upgrade_file_path} failed!"
    exit 1
  fi
  log "[INFO] untar doris v${new_version} package ok."

  # backup old bin of doris
  local bin_dir="doris/bin"
  mkdir -p ${backupDir}/doris && cp -a ${dest_dir}/${bin_dir} ${backupDir}/${bin_dir}
  if [ $? -ne 0 ]; then
    error_on_rollback "copy ${dest_dir}/${bin_dir} to ${backupDir}/${bin_dir} failed."
    exit 1
  fi

  rm -fr "${dest_dir}/${bin_dir}"
  if [ $? -ne 0 ]; then
    error_on_rollback "remove ${dest_dir}/${bin_dir} failed."
    exit 1
  fi
  echo "${backupDir}/${bin_dir},${dest_dir}/${bin_dir}" >> ${backupUpgradeDirPairList}
  log "[INFO] backup old bin of doris ok."

  # 1. check and fix start scripts (start_be.sh, start_fe.sh and start_broker.sh) 
  log "[INFO] check and fix start scripts (start_be.sh, start_fe.sh and start_broker.sh)"
  cp -a "${untar_work_dir}/${bin_dir}" "${dest_dir}/${bin_dir}"
  if [ $? -ne 0 ]; then
    error_on_rollback "copy ${untar_work_dir}/${bin_dir} to ${dest_dir}/${bin_dir} failed."
    exit 1
  fi
  chown -R doris:doris "${dest_dir}/${bin_dir}"

  echo "${dest_dir}/${bin_dir}" >> ${newAddDirList}
  log "[INFO] copy ${untar_work_dir}/${bin_dir} to ${dest_dir}/${bin_dir} ok."


  # 2. check and fix log4j.properties
  local conf_file="doris/conf/log4j.properties"
  log "[INFO] check and fix ${conf_file}"
  mkdir -p "${backupDir}/doris/conf"
  cp -a "${dest_dir}/${conf_file}" "${backupDir}/${conf_file}"
  echo "${backupDir}/${conf_file},${dest_dir}/${conf_file}" >> ${backupUpgradeDirPairList}
  rm -f "${dest_dir}/${conf_file}"
  echo "${dest_dir}/${conf_file}" >> ${newAddDirList}
  cp -a "${untar_work_dir}/${conf_file}" "${dest_dir}/${conf_file}"
  if [ $? -ne 0 ]; then
    error_on_rollback "copy ${untar_work_dir}/${conf_file} to ${dest_dir}/${conf_file} failed."
  fi
  chown doris:doris "${dest_dir}/${conf_file}"
}

check_fix_doris(){
  if [ ! -d ${sourceDir} ]; then
    log "[ERROR] ${sourceDir} is not exist"
    exit 1
  fi

  local new_version=$(echo $doris_tar | egrep -o "[0-9]\.[0-9]+" | head -1)
  if [ "${new_version}" != "1.2" ]; then
    log "[ERROR] no need to fix, the doris version is not right"
    exit 0
  fi

  # get old version
  local dest_dir="/usr/local/service"
  local doris_be_bin="${dest_dir}/doris/lib/be/doris_be"
  if [ ! -f ${doris_be_bin} ]; then
    log "[ERROR] ${doris_be_bin} not exists."
    exit -1
  fi
  local version_str=$(${doris_be_bin} --version)
  local old_version=$(echo ${version_str} | egrep -o "[0-9]\.[0-9]+" | head -1)
  log "[INFO] Found your old version string of Doris is ${old_version} (${version_str})"
  if [ "${old_version}" != "1.2" ]; then
    log "[ERROR] no need to fix, the doris version is not right, it now just fix 1.2"
    exit 0
  fi

  # check for if or not fix start scripts
  local need_to_fix=false
  local start_be_script="start_be"
  local start_fe_script="start_fe"
  local start_broker_script="start_broker"
  declare -A MD5_MAP
  MD5_MAP["${start_be_script}"]="fae585a2bef6eeb288c006922ed3735b"
  MD5_MAP["${start_fe_script}"]="d7455720d9fd4c0f04774bc4443a50f0"
  MD5_MAP["${start_broker_script}"]="895241467593aca27f021312405ea1ad"
  for myscript in ${!MD5_MAP[*]}
  do   
    local myfile="${dest_dir}/doris/bin/${myscript}.sh"
    if [ ! -f ${myfile} ]; then
      log "[ERROR] ${myfile} not exists."
      exit -1
    fi
    local md5sum=$(md5sum ${myfile} | awk '{print $1}')
    local expected_md5=${MD5_MAP[$myscript]}
    if [ "${md5sum}" != "${expected_md5}" ]; then
      log "[INFO] md5 not match, expected $expected_md5, actually $md5sum(${myfile}), need to fix..."
      need_to_fix=true
      break
    fi
  done
  if [ "${need_to_fix}" = true ]; then
    fix_start_scripts
  else
    log "[INFO] no need to fix start scripts, they are all the newest!"
  fi

  # 3. check and fix user and group related issue
  log "[INFO] check and fix user and group related issue"
  local group="doris"
  egrep "^$group" /etc/group >& /dev/null
  if [ $? -ne 0 ]; then
    groupadd $group
    if [ $? -ne 0 ]; then
      log "[WARN] Add group $group failed"
    else
      log "[INFO] Add group $group successfully!"
    fi
  else
    log "[INFO] no need to add group $group which is already exist!"
  fi

  # create user if not exists
  local user="doris"
  egrep "^$user" /etc/passwd >& /dev/null
  if [ $? -ne 0 ]; then
    useradd -g $group $user
    if [ $? -ne 0 ]; then
      log "[WARN] Add user $user to $group failed"
    else
      log "[INFO] Add user $user successfully!"
    fi
  else
    log "[INFO] no need to add user $user which is already exist!"
  fi

  # 4. check and fix owners of working dir
  log "[INFO] check and fix owners of working dir"
  change_working_dir_owner
 
  # 5. check and fix monitor.json
  log "[INFO] check and fix monitor.json"
  update_monitor_json "RESTORE"

  # 6. check and fix cdwch-agent
  log "[INFO] check and fix cdwch-agent"
  update_agent

  log "[INFO] success to check and fix doris v${old_version} according to v${new_version}."
}

usage(){
  echo "USAGE: $0 region[|-r or --rollback] package_name [-f]"
  echo "or"
  echo "$0 -r package_name"
  echo "or"
  echo "$0 -fix package_name"
  echo " e.g.: \"$0 bj tencent-cdw-doris-1.2.2-rc01-2a8a38e.tar.gz\" for upgrade from beijing bucket"
  echo " e.g.: \"$0 gz tencent-cdw-doris-1.2.2-rc01-2a8a38e.tar.gz\" for upgrade from guangzhou bucket"
  echo " e.g.: \"$0 sh tencent-cdw-doris-1.2.2-rc01-2a8a38e.tar.gz\" for upgrade from shanghai bucket"
  echo " e.g.: \"$0 nj tencent-cdw-doris-1.2.2-rc01-2a8a38e.tar.gz\" for upgrade from nanjing bucket"
  echo " e.g.: \"$0 hk tencent-cdw-doris-1.2.2-rc01-2a8a38e.tar.gz\" for upgrade from hongkong bucket"
  echo " e.g.: \"$0 cq tencent-cdw-doris-1.2.2-rc01-2a8a38e.tar.gz\" for upgrade from chongqing bucket"
  echo " e.g.: \"$0 sg tencent-cdw-doris-1.2.2-rc01-2a8a38e.tar.gz\" for upgrade from singapore bucket"
  echo " e.g.: \"$0 cd tencent-cdw-doris-1.2.2-rc01-2a8a38e.tar.gz\" for upgrade from chengdu bucket"
  echo " or \"$0 -r tencent-cdw-doris-1.2.2-rc01-2a8a38e.tar.gz\" for rollback to version tencent-cdw-doris-1.2.2-rc01-2a8a38e"
  echo " e.g.: \"$0 bj tencent-cdw-doris-1.2.2-rc01-2a8a38e.tar.gz -f\" for fix according to the version in beijing bucket"
}

create_log_file() {
  touch ${logFile}
  if [ $? -ne 0 ]; then
    echo "[ERROR] create file ${logFile} failed!"
    exit 1
  fi
}

init() {

  # two params for upgrade and rollback and three params for checking and fixing
  if [ $# -ne 2 ] && [ $# -ne 3 ] ; then
    usage $@
    exit 1;
  fi

  if [ $# -eq 3 ] && [ "$3" != "-f" ] ; then
    usage $@
    exit 1;
  fi

  doris_tar="$2"
  if [[ "${doris_tar:0:18}" != "tencent-cdw-doris-" ]]; then
    usage $@
    exit 1;
  fi

  if [[ "${doris_tar:0-7:7}" != ".tar.gz" ]]; then
    doris_tar="${doris_tar}.tar.gz"
    echo "package_name missed .tar.gz? it has been complemented with .tar.gz as suffix:${doris_tar}"
  fi

  upgrade_version_string=${doris_tar%\.tar\.gz}

  execute_mode="UPGRADE"
  if [ "$3" == "-f" ]; then
    execute_mode="CHECK_FIX"
  fi

  case $1 in
    bj|beijing)
    cos_bucket_url=${bj_cos_bucket_url}
    ;;
    gz|guangzhou)
    cos_bucket_url=${gz_cos_bucket_url}
    ;;
    sh|shanghai)
    cos_bucket_url=${sh_cos_bucket_url}
    ;;
    hk|hongkong)
    cos_bucket_url=${hk_cos_bucket_url}
    ;;
    nj|nanjing)
    cos_bucket_url=${nj_cos_bucket_url}
    ;;
    cq|chongqing)
    cos_bucket_url=${cq_cos_bucket_url}
    ;;
    sg|singapore|xinjiapo)
    cos_bucket_url=${sg_cos_bucket_url}
    ;;
    cd|chengdu)
    cos_bucket_url=${cd_cos_bucket_url}
    ;;
    -r|rollback)
    execute_mode="ROLLBACK"
    ;;
    *)
    usage $@
    exit 1
    ;;
  esac

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
  log "[INFO] start to rollback..."

  if [ ! -d ${backupDir} ]; then
    echo "[ERROR] backup dir(${backupDir}) must be exist, please check the version number ${upgrade_version_string}"
    exit 1
  fi
  create_log_file 

  # remove new add dirs
  rollback_new_add_dirs

  # restore upgrade dirs
  rollback_upgrade_dirs

  log "[INFO] rollback successfully!!"

elif [ ${execute_mode} == "CHECK_FIX" ]; then

  log "[INFO] start to check and fix according to specify version..."

  # check and fix 
  check_fix_doris

  log "[INFO] checking and fixing successfully!!"

else # for upgarde

  log "[INFO] start to upgrade..."

  # upgrade 
  upgrade_doris

  log "[INFO] upgrade successfully!!"
fi
