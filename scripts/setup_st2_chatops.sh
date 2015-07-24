#!/bin/sh
#
# env file containing environment data must be put into ./data/ directory to vagrant provisioning
# or it must be resided in same directory
#
# BOTN=bot name to connect to st2
# BOTP=bot password
# ACCN=account name to connect to st2
# ACCP=accountpassword
# SLACK_TOKEN=slack hubot integration tocken
# ANSIBLE_HOSTS_URL=if set, download ansible hosts file from this url
#
if [[ -f /vagrant/env ]]
then
. /vagrant/env
fi
if [[ -f ./env ]]
then
. ./env
fi
BOTN="${BOTN:-bot1}"
BOTP="${BOTP:-Password}"
ACCN="${ACCN:-admin}"
ACCP="${ACCP:-Password}"
SLACK_TOKEN="${SLACK_TOKEN:-xoxb-You-Tocken}"
SSTART=$(date +"%s")
#
# Force latest python six to all phython 2.7 installation
#
reset_six(){
  updatedb
  cd /tmp
  if [[ ! -f /tmp/six-1.9.0.tar.gz ]]
  then
    wget https://pypi.python.org/packages/source/s/six/six-1.9.0.tar.gz
    tar -xzf six-1.9.0.tar.gz
  fi
  cd six-1.9.0
  locate six.py | egrep "^/usr.*site-packages.*/six.py$" |xargs -L 1 cp -f ./six.py
  st2ctl stop
  st2ctl start
  sleep 20
}
#
# Prepare repositories and packages
#
yum -y install epel-release vim-enhanced mc httpd-tools
#
# Deploing StackStorm
#
cd /tmp
curl -q -k -O https://downloads.stackstorm.net/releases/st2/scripts/st2_deploy.sh
chmod +x st2_deploy.sh
#
# Correct mariadb staurtup, replace testu and testp to our values
#
sed -i "s/bash \${BOOTSTRAP_FILE} \${ST2VER}/sed -i \"s@service mysqld restart@systemctl enable mariadb.service\\\\n    service mariadb restart@\" \${BOOTSTRAP_FILE}\n    sed -i \"s@testu@${ACCN}@\" \${BOOTSTRAP_FILE}\n    sed -i \"s@testp@${ACCP}@\" \${BOOTSTRAP_FILE}\n    bash \${BOOTSTRAP_FILE} \${ST2VER}/" st2_deploy.sh
#exit 0
#
# Due to unknown mistall installation error, turning it off
#
export INSTALL_MISTRAL=0
./st2_deploy.sh latest
#
# Correct st2ctl, htpasswd and configuring hubot access to StackStorm
#
if [ ${INSTALL_MISTRAL} != "1" ]; then
  sed -ri 's/service mistral ([a-zA-Z0-9]+)/echo "service mistral \1 - disabled"/ig' /bin/st2ctl
fi
if [[ -f /etc/st2/htpasswd ]]
then
  htpasswd -mb /etc/st2/htpasswd $BOTN $BOTP
  htpasswd -D /etc/st2/htpasswd $ACCN
  htpasswd -mb /etc/st2/htpasswd $ACCN $ACCP
else
  htpasswd -cmb /etc/st2/htpasswd $BOTN $BOTP
  htpasswd -mb /etc/st2/htpasswd $ACCN $ACCP
fi
#
# Install additional packages
#
yum -y install python-pip libicu-devel mlocate cowsay sshpass libxml2-python
#
# Replacing python-six to latest version
#
#pip uninstall six
#pip install -Iv https://pypi.python.org/packages/source/s/six/six-1.9.0.tar.gz
reset_six
#
# Add hubot pack to StackStorm
#
st2 run packs.install packs=hubot,ansible register=all
#
# Installing Node.js and npm (Node.js packet manager)
#
yum -y install nodejs npm
#
# Installing redis, needed by hubot
#
yum -y install redis
systemctl enable redis.service
systemctl start redis.service
#
# Installing hubot with tools
#
npm install -g hubot coffee-script yo generator-hubot
#
# Creating hubot instance
#
sudo mkdir -p /opt/hubot
sudo chown -R stanley:stanley /opt/hubot
sudo -H -u stanley bash -c 'cd /opt/hubot && echo "n" | yo hubot --name=stanley --description="Stanley StackStorm bot" --defaults'
sudo -H -u stanley bash -c 'cd /opt/hubot && npm install hubot-slack hubot-stackstorm --save'
sudo -H -u stanley bash -c 'cd /opt/hubot && npm install hubot-xmpp --save'
sed -i 's@.*\[.*@&\n  "hubot-stackstorm",@' /opt/hubot/external-scripts.json
#
# Install ansible to system
#
yum -y install ansible
sed -i 's/#host_key_checking/host_key_checking/' /etc/ansible/ansible.cfg
#
# Copy ansible hosts file to /etc/ansible if present
#
if [[ -f /vagrant/hosts ]]
then
  cp -fv /vagrant/hosts /etc/ansible/hosts
fi
#
# Download ansible hosts file to /etc/ansible if url present
#
if [[ "$ANSIBLE_HOSTS_URL" != "" ]]
then
  curl -o /etc/ansible/hosts $ANSIBLE_HOSTS_URL 
fi
#
# Install chatops aliases to st2
#
yum -y install python-urllib*
chown -R stanley:stanley /opt/hubot
reset_six
#st2 run packs.install packs=st2-ansible-aliases register=all repo_url=armab/st2-ansible-aliases
st2 run packs.install packs=st2-chatops-aliases register=all repo_url=dreyou/st2-chatops-aliases
sleep 20
st2 run packs.install packs=st2-chatops-misc register=all repo_url=dreyou/st2-chatops-misc
sleep 20
#
# Preparing and run hubot systemctl service
#
cat > /opt/hubot/hubot.env << EOF
ST2_AUTH_USERNAME=$BOTN
ST2_AUTH_PASSWORD=$BOTP
HUBOT_SLACK_TOKEN=$SLACK_TOKEN
ST2_WEBUI_URL=http://localhost:8080
PORT=8181
EOF
cp -fv /opt/hubot/bin/hubot /opt/hubot/bin/hubot_systemctl
sed -i 's@set -e@cd /opt/hubot\nset -e@' /opt/hubot/bin/hubot_systemctl
cat > /usr/lib/systemd/system/hubot.service << EOF
[Unit]
Description=Hubot instance daemon
After=network.target

[Service]
EnvironmentFile=/opt/hubot/hubot.env
ExecStart=/opt/hubot/bin/hubot_systemctl --name stanley --adapter slack --alias !
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=42s

[Install]
WantedBy=multi-user.target
EOF
systemctl enable hubot.service
systemctl daemon-reload
systemctl start hubot.service
sleep 20
#
# Send alive message
#
st2 run hubot.post_message channel=general message="I'm here"
#
# Example hubot startup with slack adapter
#
#cd /opt/hubot && ST2_AUTH_USERNAME=$BOTN ST2_AUTH_PASSWORD=$BOTP HUBOT_SLACK_TOKEN=$SLACK_TOKEN ST2_WEBUI_URL=http://localhost:8080 PORT=8181 bin/hubot --name stanley --adapter slack --alias !
#
# Example hubot startup with xmpp adapter
#
#cd /opt/hubot && ST2_AUTH_USERNAME=$BOTN ST2_AUTH_PASSWORD=$BOTP HUBOT_XMPP_USERNAME=bot1@bank.rpb.ru HUBOT_XMPP_ROOMS=chatops@conference.bank.rpb.ru HUBOT_XMPP_PASSWORD=Rhjrjlbk1 HUBOT_XMPP_HOST=logcollector PORT=8181 bin/hubot --name stanley --adapter xmpp --alias !
#
# Print execution time
#
SSTOP=$(date +"%s")
SDIFF=$(($SSTART-$SSTOP))
echo "Install script finished in $(($SDIFF / 60)) min. $(($SDIFF % 60)) sec."
exit 0
