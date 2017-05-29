#!/bin/bash

mkdir /root/serve
exec > /root/serve/logs.txt 2>&1 # log all output to that file
set -e -x

function onerror {
  curl --data "{\"full_name\": \"{{STATUS_SERVER_FULL_NAME}}\", \"branch\": \"{{BRANCH}}\", \"installation_id\": {{GITHUB_INSTALLATION_ID}}, \"ip\": \"$FEATURE_DEPLOY_IP\", \"hash\": \"{{GITHASH}}\", \"secret\": \"{{STATUS_SERVER_SECRET}}\"}" https://featuredeploy.herokuapp.com/error -H "Content-Type: application/json"
}
trap onerror EXIT

apt-get -y update
apt-get install -y webfs
/etc/init.d/webfs stop # gets started right after install

cd /root/serve
ufw allow 80
webfsd -p 80 -f logs.txt -b {{HTTP_AUTH_USER}}:{{HTTP_AUTH_PASS}}
cd /root

cat > ~/startup <<- 'UniqueText550e8400e29b11d4a716446655440000'
{{STARTUP}}
UniqueText550e8400e29b11d4a716446655440000
chmod 744 ~/startup

FEATURE_DEPLOY_IP=$(curl http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)
export FEATURE_DEPLOY_IP

fallocate -l 8G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
swapon -s

cat > /root/self_destroy <<- SelfDestroy
  (cd /root/app/featuredeploy
  curl --data '{"secret": "{{STATUS_SERVER_SECRET}}", "full_name": "{{STATUS_SERVER_FULL_NAME}}", "branch": "{{BRANCH}}", "installation_id": {{GITHUB_INSTALLATION_ID}}}' {{STATUS_SERVER_URL}}destroy -H "Content-Type: application/json"
  curl -X DELETE -H 'Content-Type: application/json' -H 'Authorization: Bearer {{DIGITAL_OCEAN_TOKEN}}' 'https://api.digitalocean.com/v2/droplets/$(curl -s http://169.254.169.254/metadata/v1/id)')
SelfDestroy

cat /root/self_destroy | at "now + 2 days"

# install tools
curl -sSL https://github.com/docker/compose/releases/download/1.8.0/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
curl -sS https://bootstrap.pypa.io/get-pip.py | python - "pip==8.1.2"
update-rc.d -f  apache2 remove # makes and install of apache not start it
sudo apt-get install -y apache2
sudo apt-get install -y build-essential
sudo apt-get install -y python-dev

# checkout the project
cat > ~/.ssh/id_rsa <<- MyPrivateKey
{{PRIVATE_SSH_KEY}}
MyPrivateKey
chmod 400 ~/.ssh/id_rsa
ssh-keyscan -H github.com >> ~/.ssh/known_hosts
git clone {{GIT_CLONE}} app
rm ~/.ssh/id_rsa

cd app
git checkout {{GITHASH}}


:
:
:
:
:
: '        +++++++++++++++++++++++'
: '        +++ Running startup +++'
: '        +++++++++++++++++++++++'
:
set +x
{{SETENVS}} ~/startup
set -x
:
:
:
:
:
: '++++++++++++++++++++++++++++++++'
: '+++ Finished running startup +++'
: '++++++++++++++++++++++++++++++++'
:

# setup apache2 as a proxy
htpasswd -bc /etc/apache2/.htpasswd '{{HTTP_AUTH_USER}}' '{{HTTP_AUTH_PASS}}' # "'" is not escaped
cat > /etc/apache2/ports.conf <<- MyApacheConfig
Listen 80
<Location "/">
    AuthType Basic
    AuthName 'Enter test'
    AuthUserFile '/etc/apache2/.htpasswd'
    Require valid-user
    Order deny,allow
    Deny from all
    # Wirecard servers for HTTP callback, documented here: https://guides.wirecard.at/ipaddresschange:de
    Allow from 185.60.56.35
    Allow from 185.60.56.36
    Allow from 195.93.244.97
    Satisfy Any
    ProxyPass http://localhost:8000/
    ProxyPassReverse http://localhost:8000/
</Location>
<IfModule ssl_module>
        Listen 443
</IfModule>
<IfModule mod_gnutls.c>
        Listen 443
</IfModule>
MyApacheConfig

a2enmod proxy
a2enmod proxy_http

 # kill the previous server on port 80 (yiiiihaaaahh!)
pkill webfsd

/etc/init.d/apache2 start

MESSAGE="Ready to test: http://$FEATURE_DEPLOY_IP/ {{GITHASH}} {{BRANCH}}"
curl -H "Content-Type: application/json" \
    -X POST \
    -d "{\"color\": \"purple\", \"message_format\": \"text\", \"message\": \"$MESSAGE\" }" \
    https://api.hipchat.com/v2/room/{{HIPCHAT_ROOM_ID}}/notification?auth_token={{HIPCHAT_TOKEN}}

curl --data "{\"secret\": \"{{STATUS_SERVER_SECRET}}\", \"full_name\": \"{{STATUS_SERVER_FULL_NAME}}\", \"branch\": \"{{BRANCH}}\", \"installation_id\": {{GITHUB_INSTALLATION_ID}}, \"ip\": \"$FEATURE_DEPLOY_IP\", \"hash\": \"{{GITHASH}}\"}" {{STATUS_SERVER_URL}}deployed -H "Content-Type: application/json"