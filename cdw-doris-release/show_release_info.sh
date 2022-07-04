cd /data/doris-1.x/cdw-doris-release
git log dev-1.1.2 | head -n 3 | grep commit | awk '{print $2" (dev-1.1.2)"}'
ls -l | grep cdw_doris_v1 | awk '{print $5,$6,$7,$8}'
md5sum cdw_doris_v1.1.tar.gz
md5sum doris/lib/be/doris_be
md5sum doris/lib/fe/doris-fe.jar
