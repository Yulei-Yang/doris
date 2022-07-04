
echo "begin stop broker"
sh /usr/local/service/doris/bin/stop_broker.sh 
sleep 1
echo "begin start broker"
sh /usr/local/service/doris/bin/start_broker.sh --daemon
