#!/usr/bin/env bash
#set -x

HOME_DIR=`pwd`
PREFIX_DIR=$HOME_DIR/cdw-doris-release
if [ ! -d ${PREFIX_DIR} ]; then
  echo "[ERROR] ${PREFIX_DIR} dir is not exist"
  exit -1
fi

cd $PREFIX_DIR
# build lib directory
echo "[INFO] clean ${PREFIX_DIR}/lib"
rm -fr lib
mkdir lib
echo "[INFO] deploy ${PREFIX_DIR}/lib"

# install fe libs
cp -a $HOME_DIR/output/fe/lib lib/fe
mv lib/fe/help-resource.zip lib/

# install be libs
rm -fr lib/be/debug_info
mkdir -p lib/be
cp -a $HOME_DIR/output/be/lib/doris_be lib/be/
cp -a $HOME_DIR/output/be/lib/{hadoop_hdfs,java_extensions} lib/

# install broker libs
cp -a $HOME_DIR/fs_brokers/apache_hdfs_broker/output/apache_hdfs_broker/lib lib/broker

# install tencent libs
cp -a ${PREFIX_DIR}/tencent_libs/*.jar lib/broker
cp -a ${PREFIX_DIR}/tencent_libs/*.jar lib/fe

# build plugins directory
echo "[INFO] clean ${PREFIX_DIR}/plugins"
rm -fr plugins
echo "[INFO] deploy ${PREFIX_DIR}/plugins"
mkdir -p plugins/AuditLoader
cd plugins/AuditLoader
cp $HOME_DIR/fe_plugins/auditloader/target/auditloader.zip .
unzip auditloader.zip
rm auditloader.zip
cd -

# build other directories
echo "[INFO] deploy udf, spark-dpp, webroot and www"
cp -a $HOME_DIR/output/udf .
cp -a $HOME_DIR/output/fe/spark-dpp .
cp -a $HOME_DIR/output/fe/webroot .
cp -a $HOME_DIR/output/be/www .

echo "[INFO] successfully deployed"
