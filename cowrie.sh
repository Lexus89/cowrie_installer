#!/bin/bash
# Code to automatically install cowrie SSH honeypot
#
# Examples: 
# ./cowrie.sh [/install/path/..]

installdir=$1

WHOAMI=`whoami`

if [ "$WHOAMI" != "root" ] ; then
	echo -e "\033[0;31m[!]\033[0m Script needs to run as root"
	exit 0;
fi

if [ $# -eq 0 ] ; then
	echo -e "\033[0;31m[!]\033[0m No arguments supplied"
	exit 0;
fi

if [ ! -d $installdir ] ; then
	echo -e "\033[0;31m[!]\033[0m Given path does not exist"
	exit 0;
fi

set -e
set -x

apt-get update
apt-get -y -f install libssl-dev libffi-dev build-essential libpython3-dev python3-minimal authbind virtualenv

pip3 install -U supervisor
/etc/init.d/supervisor start || true

if [ -e "/etc/ssh/sshd_config" ]; then 
	sed -i 's/Port 22$/Port 2222/g' /etc/ssh/sshd_config
	service ssh restart
fi

if getent passwd cowrie > /dev/null 2>&1; then
	echo "user 'cowrie' exists"
else
	useradd -d /home/cowrie -s /bin/bash -m cowrie -g users
fi

cd $installdir
git clone https://github.com/cowrie/cowrie.git cowrie

# Config for requirements.txt
#cat > $installdir/cowrie/requirements.txt <<EOF
#twisted>=17.1.0
#cryptography>=0.9.1,<=1.8
#configparser
#pyopenssl
#pyparsing
#packaging
#appdirs>=1.4.0
#pyasn1_modules
#attrs
#service_identity
#python-dateutil
#tftpy
#EOF

cd cowrie
virtualenv --python=python3 cowrie-env #env name has changed to cowrie-env on latest version of cowrie
source cowrie-env/bin/activate
# without the following, i get this error:
# Could not find a version that satisfies the requirement csirtgsdk (from -r requirements.txt (line 10)) (from versions: 0.0.0a5, 0.0.0a6, 0.0.0a5.linux-x86_64, 0.0.0a6.linux-x86_64, 0.0.0a3)
pip3 install csirtgsdk==0.0.0a6
pip3 install -r requirements.txt 

cd etc
cp cowrie.cfg.dist cowrie.cfg
sed -i 's/hostname = svr04/hostname = server/g' cowrie.cfg
sed -i 's/listen_endpoints = tcp:2222:interface=0.0.0.0/listen_endpoints = tcp:22:interface=0.0.0.0/g' cowrie.cfg
sed -i 's/version = SSH-2.0-OpenSSH_6.0p1 Debian-4+deb7u2/version = SSH-2.0-OpenSSH_6.7p1 Ubuntu-5ubuntu1.3/g' cowrie.cfg
sed -i 's/#\[output_hpfeeds\]/[output_hpfeeds]/g' cowrie.cfg
sed -i '/\[output_hpfeeds\]/!b;n;cenabled = true' cowrie.cfg
sed -i "s/#server = hpfeeds.mysite.org/server = $HPF_HOST/g" cowrie.cfg
sed -i "s/#port = 10000/port = $HPF_PORT/g" cowrie.cfg
sed -i "s/#identifier = abc123/identifier = $HPF_IDENT/g" cowrie.cfg
sed -i "s/#secret = secret/secret = $HPF_SECRET/g" cowrie.cfg
sed -i 's/#debug=false/debug=false/' cowrie.cfg
cd ..

chown -R cowrie:users $installdir/cowrie/
touch /etc/authbind/byport/22
chown cowrie /etc/authbind/byport/22
chmod 770 /etc/authbind/byport/22

# start.sh is deprecated on new Cowrie version and substituted by "bin/cowrie [start/stop/status]"
sed -i 's/AUTHBIND_ENABLED=no/AUTHBIND_ENABLED=yes/' bin/cowrie
sed -i 's/DAEMONIZE=""/DAEMONIZE="-n"/' bin/cowrie

# Config for supervisor
cat > /etc/supervisor/conf.d/cowrie.conf <<EOF
[program:cowrie]
command=$installdir/cowrie/bin/cowrie start
directory=$installdir/cowrie
stdout_logfile=$installdir/cowrie/var/log/cowrie/cowrie.out
stderr_logfile=$installdir/cowrie/var/log/cowrie/cowrie.err
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=cowrie
EOF

supervisorctl update
