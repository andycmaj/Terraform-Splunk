#!/usr/bin/env bash
set -e

SERVICE_NAME=$1

echo "Installing dependencies..."
if [ -x "$(command -v apt-get)" ]; then
  sudo apt-get update -y
  sudo apt-get install -y unzip
else
  sudo yum update -y
  sudo yum install -y unzip wget
fi

echo "Fetching Consul..."
CONSUL=0.7.1
cd /tmp
wget https://releases.hashicorp.com/consul/$${CONSUL}/consul_$${CONSUL}_linux_amd64.zip -O consul.zip

echo "Installing Consul..."
unzip consul.zip >/dev/null
chmod +x consul
sudo mv consul /usr/local/bin/consul
sudo mkdir -p /opt/consul/data

# Read from the file we created
SERVER_COUNT=$(cat /tmp/consul-server-count | tr -d '\n')
CONSUL_JOIN=$(cat /tmp/consul-server-addr | tr -d '\n')

INSTANCE_IP="$(curl http://169.254.169.254/latest/meta-data/local-ipv4)"

# Write the flags to a temporary file
cat >/tmp/consul_flags << EOF
CONSUL_FLAGS="${consul_params}"
EOF

if [ -f /tmp/upstart.conf ];
then
  echo "Installing Upstart service..."
  sudo mkdir -p /etc/consul.d

  if [ ! -z "$SERVICE_NAME" ]; then
    sudo mkdir -p /etc/dnsmasq.d
    sudo echo "server=/consul/127.0.0.1#8600" | sudo tee /etc/dnsmasq.d/10-consul
    sudo apt-get install -y dnsmasq
    sudo echo '{"service": {"name": "'"$SERVICE_NAME"'", "port": 8089}}' | sudo tee /etc/consul.d/cluster-master.json
  fi

  sudo mkdir -p /etc/service
  sudo chown root:root /tmp/upstart.conf
  sudo mv /tmp/upstart.conf /etc/init/consul.conf
  sudo chmod 0644 /etc/init/consul.conf
  sudo mv /tmp/consul_flags /etc/service/consul
  sudo chmod 0644 /etc/service/consul
else
  echo "Installing Systemd service..."
  sudo mkdir -p /etc/systemd/system/consul.d
  sudo chown root:root /tmp/consul.service
  sudo mv /tmp/consul.service /etc/systemd/system/consul.service
  sudo chmod 0644 /etc/systemd/system/consul.service
  sudo mv /tmp/consul_flags /etc/sysconfig/consul
  sudo chown root:root /etc/sysconfig/consul
  sudo chmod 0644 /etc/sysconfig/consul
fi
