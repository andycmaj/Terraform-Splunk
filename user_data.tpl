#!/bin/bash
set -x
exec 1> /var/tmp/mylog 2>&1



INSTANCE_IP="$(curl http://169.254.169.254/latest/meta-data/local-ipv4)"

# Create local config files
sudo -u splunk mkdir -p /opt/splunk/etc/system/local

cat <<EOF | sudo -u splunk tee /opt/splunk/etc/system/local/deploymentclient.conf
${deploymentclient_conf_content}
EOF

cat <<EOF | sudo -u splunk tee /opt/splunk/etc/system/local/web.conf
${web_conf_content}
EOF

cat <<EOF | sudo -u splunk tee /opt/splunk/etc/system/local/server.conf
${server_conf_content}
EOF
sed -i 's/LOCAL_IP/'$${INSTANCE_IP}'/' /opt/splunk/etc/system/local/server.conf

cat <<EOF | sudo -u splunk tee /opt/splunk/etc/system/local/serverclass.conf
${serverclass_conf_content}
EOF

# Update hostname
hostname splunk-${role}-`hostname`
echo `hostname` > /etc/hostname
sed -i 's/localhost$/localhost '`hostname`'/' /etc/hosts


# Start service and Enable autostart
sudo -u splunk /opt/splunk/bin/splunk enable boot-start -user splunk --accept-license

export SPLUNK_START_ARGS=--accept-license --answer-yes --no-prompt
${cmds_content}

# sudo -u splunk /opt/splunk/bin/splunk start --accept-license
sudo -u splunk /opt/splunk/bin/entrypoint.sh start-service
