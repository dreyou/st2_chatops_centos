#!/bin/sh
BOTN="${BOTN:-bot1}"
BOTP="${BOTP:-Password}"
ACCN="${ACCN:-admin}"
ACCP="${ACCP:-Password}"
SLACK_TOKEN="${SLACK_TOKEN:-xoxb-7202440977-diPqXLBhimB8aehG8TIKpmRE}"
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
yum -y install python-pip libicu-devel mlocate cowsay sshpass
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
yum -y install ansible
sed -i 's/#host_key_checking/host_key_checking/' /etc/ansible/ansible.cfg
cp -f /vagrant/hosts /etc/ansible/hosts
#
# Install ansible to system
#
yum -y install python-urllib*
chown -R stanley:stanley /opt/hubot
reset_six
#st2 run packs.install packs=st2-ansible-aliases register=all repo_url=armab/st2-ansible-aliases
st2 run packs.install packs=st2-chatops-aliases register=all repo_url=dreyou/st2-chatops-aliases
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
cp -fv /vagrant/hubot.service /usr/lib/systemd/system/
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
