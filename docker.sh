#systemctl start docker
#docker pull apache/doris:build-env-for-2.0
#docker rm -f $(docker ps -a -q)
docker run -it -v /data/TCHouse-D/.m2:/root/.m2 -v /data/TCHouse-D/:/data/TCHouse-D  --name TCHouse-D -d apache/doris:build-env-for-2.0
docker exec -it TCHouse-D /bin/bash
