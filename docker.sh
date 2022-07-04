systemctl start docker
#docker pull apache/doris:build-env-ldb-toolchain-latest
docker pull apache/doris:build-env-for-2.0
docker rm -f $(docker ps -a -q)
#docker run -it -v /data/doris-2.x/.m2:/root/.m2 -v /data/doris-2.x/:/data/doris-2.x  --name doris-2.x -d apache/doris:build-env-ldb-toolchain-latest
docker run -it -v /data/doris-2.x/.m2:/root/.m2 -v /data/doris-2.x/:/data/doris-2.x  --name doris-2.x -d apache/doris:build-env-for-2.0
docker exec -it doris-2.x /bin/bash
