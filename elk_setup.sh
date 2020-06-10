#!/bin/bash
# This install script is for IBM Security Taipei Lab hackday event to install ELK on Ubuntu18.04

set -x

apt-get update
apt-get install openjdk-8-jre apt-transport-https wget nginx -y

# Install repo of Elastic
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
echo 'deb https://artifacts.elastic.co/packages/6.x/apt stable main' | tee -a /etc/apt/sources.list.d/elastic.list
apt-get update

apt-get install elasticsearch kibana -y
sed -i -e 's/#server.host: "localhost"/server.host: "localhost"/' /etc/kibana/kibana.yml
echo 'network.host: 0.0.0.0' | tee -a /etc/elasticsearch/elasticsearch.yml
echo 'http.port: 9200' | tee -a /etc/elasticsearch/elasticsearch.yml
echo "Restarting Kibana and Elasticsearch..."
systemctl restart kibana
systemctl start elasticsearch

# Nginx part
echo "admin:`openssl passwd -apr1 admin`" | tee -a /etc/nginx/htpasswd.kibana
cat > /etc/nginx/sites-available/kibana <<EOF
server {
    listen 80 default_server;
    server_name _;

    auth_basic "Restricted Access";
    auth_basic_user_file /etc/nginx/htpasswd.kibana;

    location / {
        proxy_pass http://localhost:5601;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
rm /etc/nginx/sites-enabled/default
ln -s /etc/nginx/sites-available/kibana /etc/nginx/sites-enabled/kibana

echo "Restarting Nginx..."
systemctl restart nginx.service

apt-get install logstash -y
#Change the ip address below to yours
echo 'http.host: "your ip address"' | tee -a /etc/logstash/logstash.yml
cat > /etc/logstash/conf.d/sysflow_demo.conf <<EOF
input {
  syslog {
    port => 5144
  }
}

output {
  elasticsearch {
    hosts => ["http://localhost:9200"]
    index => "sysflow-demo-1"
  }
}
EOF
/usr/share/logstash/bin/logstash -f /etc/logstash/conf.d/sysflow_demo.conf > /dev/null 2>&1
for i in {1..60}
do
    netstat -ntlp | grep 5144
    RET=$(echo $?)
    if [ $RET -eq 0 ]; then
        echo "Logstash is started successfully on port 5144"
        echo "You could send your Sysflow log to logstash 5144 port"
        break
    fi
    sleep 1s
    if [ $i -eq 60 ]; then
        echo "Logstash is not started in 60s"
    fi
done
