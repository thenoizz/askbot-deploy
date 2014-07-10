#!/bin/bash

# Copyright 2014 Dorin Paslaru, Cloudbase Solutions S.R.L. (http://cloudbase.it)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# Use it at your own peril and, quite frankly, it probably won’t work for 
# you :).  But you may be desperate enough to tr it.
#
# See the License for the specific language governing permissions and
# limitations under the License.
#
# !!! Note: run this script from it's root directory
#
# ############################################################################

# Tested on Ubuntu 14.04

set -e

EXPECTED_ARGS=6
E_BADARGS=65

if [ $# -ne $EXPECTED_ARGS ]
then
  echo "Not enough args. Usage: $0 db_name db_user db_pass work_dir ip_addr domain"
  exit $E_BADARGS
fi

db_name=${1} 		# database name to be used
db_user=${2} 		# username for db
db_pass=${3} 		# password for db
work_dir=${4}		# the directory where askbot will be installed
ip_addr=${5}		# ip address of the host. if not supplied, it will use the eth0 ip address
domain=${6}			# domain name for the deploymet, used in the apache conf. If it is empty, 'example.com' will be used 
deploy_dir=`pwd` 	# the directory where this script is.

# get the eth0 ip is the param is empty
if [ -z "$ip_addr" ]; then
	ip_addr = `/sbin/ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}'`
fi

if [ -z "$domain" ]; then
	domain = "example.com"
fi

read -p "This script will install Askbot in $work_dir and deploy it using Apache. Press [Enter] key to continue..."

# create work_dir if it doesn't exist
if [ ! -d "$work_dir" ]; then
  sudo mkdir $work_dir
  sudo chown $USER $work_dir
fi

# apt update & upgrade
echo -e "\n"
read -p "APT update and upgrade. Press [Enter] key to continue..."
sudo apt-get update -y
sudo apt-get upgrade -y

# install stuff
echo -e "\n"
read -p "Starting python-virtualenv git libpq-dev python-dev postgresql postgresql-contrib installation. Press [Enter] key to continue..."
sudo apt-get install python-virtualenv git libpq-dev python-dev postgresql postgresql-contrib -y
sudo easy_install -U pip
sudo pip install -U mock

echo -e "\n"
read -p "Cloning Askbot from github into $work_dir/_askbot-devel. Press [Enter] key to continue..."
git clone git://github.com/ASKBOT/askbot-devel.git $work_dir/_askbot-devel
cd $work_dir/_askbot-devel

echo -e "\n"
read -p "Installing Askbot. Press [Enter] key to continue..."
sudo python setup.py install -v

echo -e "\nRemoving the git clone since it's no longer needed."
cd $work_dir
sudo rm -rf _askbot-devel

#create user and db
echo -e "\n"
read -p "Creating $db_name database with db_userame: $db_user and password: $db_pass. Press [Enter] key to continue..."
sudo pip install psycopg2
sudo -u postgres psql -U postgres -c "create role $db_user with createdb login encrypted password '$db_pass';"
sudo -u postgres psql -U postgres -c "create database $db_name with owner=$db_user;"

# get the hba_conf path
hba_path=`sudo -u postgres psql -U postgres -c "show hba_file;" | awk 'NR==3 {print $1}'`

echo -e "\nEditing the hba_file"
sudo sed -i "1s/^/local   "$db_name"             "$db_user"                                md5 \n/" $hba_path

echo -e "\nRestart postgresql"
sudo /etc/init.d/postgresql restart
cd $work_dir

echo -e "\n"
read -p "Starting Askbot setup. Press [Enter] key to continue..."
askbot-setup -n . -e 1 -d $db_name -u $db_user -p $db_pass –domain=example.com

echo -e "\n"
read -p "Starting python manage.py collectstatic. Press [Enter] key to continue..."
python manage.py collectstatic

echo -e "\n"
read -p "Starting python manage.py syncdb. Press [Enter] key to continue..."
python manage.py syncdb || true
python manage.py syncdb

echo -e "\n"
read -p "Starting python manage.py migrate askbot. Press [Enter] key to continue..."
python manage.py migrate askbot

echo -e "\n"
read -p "Starting python manage.py migrate django_authopenid. Press [Enter] key to continue..."
python manage.py migrate django_authopenid #embedded login application

############
## This is for testing the install using the django webserver.
# sudo python manage.py runserver ip_addr:8000
###########

# Apache and mod_wsgi
echo -e "\n"
read -p "Starting apache2 and mod_wsgi deployment. Press [Enter] key to continue..."
sudo apt-get install apache2 apache2.2-common apache2-mpm-prefork apache2-utils libexpat1 ssl-cert libapache2-mod-wsgi -y
sudo service apache2 stop

echo -e "\nConfiguring $domain.conf file"
cp $deploy_dir/askbot_apache_default.conf $work_dir/$domain.conf
sed -i "s#/workdir#"$work_dir"#g" $work_dir/$domain.conf
sed -i "s#127.0.0.1#"$ip_addr"#g" $work_dir/$domain.conf
sed -i "s#domain-name#"$domain"#g" $work_dir/$domain.conf

echo -e "\nCopying askbot_apache_default.conf to apache direcory"
sudo cp $work_dir/$domain.conf /etc/apache2/sites-available/$domain.conf

echo -e "\nCreate logdir and socket dir"
sudo mkdir /var/log/apache2/$domain
sudo mkdir $work_dir/socket

echo -e "\nFixing permisssions..."
cd $work_dir
cd .. #go one level up
sudo chown -R $USER:www-data $work_dir
chmod -R g+w $work_dir/askbot/upfiles
chmod -R g+w $work_dir/log
chmod -R g+w $work_dir/socket

echo -e "\nEnabling mod_rewrite and $domain"
sudo a2enmod rewrite
sudo a2ensite $domain

echo -e "\nStart apache2"
sudo service apache2 start

echo -e "\nFinished the deployment. Visit http://$ip_addr or http://$domain to test it."
exit 0
