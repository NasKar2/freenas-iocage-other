#!/bin/sh
# Build an iocage jail under FreeNAS 11.1 with  Wordpress
# https://github.com/NasKar2/sepapps-freenas-iocage

# Check for root privileges
if ! [ $(id -u) = 0 ]; then
   echo "This script must be run with root privileges"
   exit 1
fi

# Initialize defaults
JAIL_IP=""
DEFAULT_GW_IP=""
INTERFACE=""
VNET="off"
POOL_PATH=""
APPS_PATH=""
WP_DATA=""


SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
. $SCRIPTPATH/wp-config
CONFIGS_PATH=$SCRIPTPATH/configs
DB_ROOT_PASSWORD=$(openssl rand -base64 16)
if [ -z $DB_PASSWORD  ]; then
   DB_PASSWORD=$(openssl rand -hex 10)
fi
echo "the DB_PASSWORD ${DB_PASSWORD}"
ADMIN_PASSWORD=$(openssl rand -base64 12)


# Check for wp-config and set configuration
if ! [ -e $SCRIPTPATH/wp-config ]; then
  echo "$SCRIPTPATH/wp-config must exist."
  exit 1
fi

# Check that necessary variables were set by wp-config
if [ -z $JAIL_IP ]; then
  echo 'Configuration error: JAIL_IP must be set'
  exit 1
fi
if [ -z $DEFAULT_GW_IP ]; then
  echo 'Configuration error: DEFAULT_GW_IP must be set'
  exit 1
fi
if [ -z $INTERFACE ]; then
  echo 'Configuration error: INTERFACE must be set'
  exit 1
fi
if [ -z $POOL_PATH ]; then
  echo 'Configuration error: POOL_PATH must be set'
  exit 1
fi

if [ -z $APPS_PATH ]; then
  echo 'Configuration error: APPS_PATH must be set'
  exit 1
fi

if [ -z $JAIL_NAME ]; then
  echo 'Configuration error: JAIL_NAME must be set'
  exit 1
fi

if [ -z $WP_DATA ]; then
  echo 'Configuration error: WP_DATA must be set'
  exit 1
fi

#
# Create Jail

# php 7.1
#echo '{"pkgs":["nano","rsync","nginx","mariadb102-server","php71","php71-mcrypt","mod_php71","php71-mbstring","php71-curl","php71-zlib","php71-gd","php71-json","php71-mysqli"]}' > /tmp/pkg.json

#php 7.2
echo '{"pkgs":["nano","rsync","nginx","mariadb102-server","php72","php72-mysqli","php72-session","php72-xml","php72-hash","php72-ftp","php72-curl","php72-tokenizer","php72-zlib","php72-zip","php72-filter","php72-gd","php72-openssl"]}' > /tmp/pkg.json

iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r 11.1-RELEASE ip4_addr="${INTERFACE}|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}"

rm /tmp/pkg.json

mkdir -p ${POOL_PATH}/${APPS_PATH}/${WP_DATA} 
echo "mkdir -p '${POOL_PATH}/${APPS_PATH}/${WP_DATA}'"

wp_config=${POOL_PATH}/${APPS_PATH}/${WP_DATA}
iocage exec ${JAIL_NAME} 'sysrc ifconfig_epair0_name="epair0b"'

#
# mount ports so they can be accessed in the jail
iocage fstab -a ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${wp_config} /config nullfs rw 0 0
iocage restart ${JAIL_NAME}
  
iocage exec ${JAIL_NAME} sysrc mysql_enable="YES"
iocage exec ${JAIL_NAME} service mysql-server start

iocage exec ${JAIL_NAME} sysrc nginx_enable="YES"
iocage exec ${JAIL_NAME} service nginx start
iocage exec ${JAIL_NAME} cp /mnt/configs/www.conf /usr/local/etc/php-fpm.d/www.conf
iocage exec ${JAIL_NAME} ln -s /usr/local/etc/php.ini-production /usr/local/etc/php.ini
iocage exec ${JAIL_NAME} sysrc php_fpm_enable="YES"
iocage exec ${JAIL_NAME} service php-fpm restart
service nginx restart
#iocage exec ${JAIL_NAME} echo "<?php phpinfo(); ?>" | tee /config/phpinfo.php
iocage exec ${JAIL_NAME} cp /mnt/configs/php-fpm.conf /usr/local/etc/php-fpm.conf

#
# start nginx and copy nginx.conf with jail IP adddress
#iocage exec ${JAIL_NAME} service nginx start
iocage exec ${JAIL_NAME} cp -f /mnt/configs/nginx.wp.conf /usr/local/etc/nginx/nginx.conf
iocage exec ${JAIL_NAME} sed -i '' "s/youripaddress/${JAIL_IP}/" /usr/local/etc/nginx/nginx.conf

# mysql_secure_installation
#iocage exec ${JAIL_NAME} 
#iocage exec ${JAIL_NAME} service mysql-server start
#iocage exec ${JAIL_NAME} service nginx start
iocage exec ${JAIL_NAME} cp -f /mnt/configs/nginx.wp.conf /usr/local/etc/nginx/nginx.conf
iocage exec ${JAIL_NAME} sed -i '' "s/youripaddress/${JAIL_IP}/" /usr/local/etc/nginx/nginx.conf

iocage exec ${JAIL_NAME} mkdir -p /var/log/nginx
iocage exec ${JAIL_NAME} touch /var/log/nginx/access.log
iocage exec ${JAIL_NAME} touch /var/log/nginx/error.log
iocage exec ${JAIL_NAME} rm /usr/local/www/nginx
iocage exec ${JAIL_NAME} mkdir /usr/local/www/nginx
iocage exec ${JAIL_NAME} cp /usr/local/www/nginx-dist/index.html /usr/local/www/nginx
#iocage exec ${JAIL_NAME} -- touch /config/phpinfo.php
#iocage exec ${JAIL_NAME} -- echo "<?php phpinfo(); ?>" > /config/phpinfo.php
iocage exec ${JAIL_NAME} service nginx restart

#
# PHP
iocage exec ${JAIL_NAME} cp /mnt/configs/www.conf /usr/local/etc/php-fpm.d/www.conf
iocage exec ${JAIL_NAME} ln -s /usr/local/etc/php.ini-production /usr/local/etc/php.ini
#iocage exec ${JAIL_NAME} sysrc php_fpm_enable="YES"
iocage exec ${JAIL_NAME} service php-fpm restart
iocage exec ${JAIL_NAME} service nginx restart
#iocage exec ${JAIL_NAME} echo "<?php phpinfo(); ?>" | tee /config/phpinfo.php
#iocage exec ${JAIL_NAME} cp /mnt/configs/php-fpm.conf /usr/local/etc/php-fpm.conf

# Secure database, set root password, create wordpress DB, user, and password
echo "Secure database"
iocage exec ${JAIL_NAME} mysql -u root -e "CREATE DATABASE ${JAIL_NAME};"
iocage exec ${JAIL_NAME} mysql -u root -e "GRANT ALL ON ${JAIL_NAME}.* TO ${JAIL_NAME}@localhost IDENTIFIED BY '${DB_PASSWORD}';"
iocage exec ${JAIL_NAME} mysql -u root -e "DELETE FROM mysql.user WHERE User='';"
iocage exec ${JAIL_NAME} mysql -u root -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
iocage exec ${JAIL_NAME} mysql -u root -e "DROP DATABASE IF EXISTS test;"
iocage exec ${JAIL_NAME} mysql -u root -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
iocage exec ${JAIL_NAME} mysql -u root -e "UPDATE mysql.user SET Password=PASSWORD('${DB_PASSWORD}') WHERE User='root';"
iocage exec ${JAIL_NAME} mysqladmin reload
iocage exec ${JAIL_NAME} cp -f /mnt/configs/my.cnf /root/.my.cnf
iocage exec ${JAIL_NAME} sed -i '' "s|mypassword|${DB_PASSWORD}|" /root/.my.cnf


touch /root/wpdatabase.txt
echo ${DB_ROOT_PASSWORD} >> wpdatabase.txt

iocage exec ${JAIL_NAME} service php-fpm restart

#
# Install wordpress
iocage exec ${JAIL_NAME} -- cd /
iocage exec ${JAIL_NAME} fetch http://wordpress.org/latest.tar.gz
iocage exec ${JAIL_NAME} tar xzvf latest.tar.gz
iocage exec ${JAIL_NAME} rm latest.tar.gz
#iocage exec ${JAIL_NAME} cd /wordpress
iocage exec ${JAIL_NAME} cp /wordpress/wp-config-sample.php /wordpress/wp-config.php
iocage exec ${JAIL_NAME} sed -i '' "s/database_name_here/${JAIL_NAME}/" /wordpress/wp-config.php
iocage exec ${JAIL_NAME} sed -i '' "s/username_here/${JAIL_NAME}/" /wordpress/wp-config.php
iocage exec ${JAIL_NAME} sed -i '' "s/password_here/${DB_PASSWORD}/" /wordpress/wp-config.php
iocage exec ${JAIL_NAME} rsync -avP -q /wordpress/ /config
#iocage exec ${JAIL_NAME} rm -r /wordpress
iocage exec ${JAIL_NAME} chown -R www:www /config
#iocage exec ${JAIL_NAME} sed -i '' "s/password_here/try_files $uri $uri/ /index.php?q=$uri&$args;/" /usr/local/etc/nginx/nginx.conf

echo "Wordpress installed"

#
# Make pkg upgrade get the latest repo
iocage exec ${JAIL_NAME} mkdir -p /usr/local/etc/pkg/repos/
iocage exec ${JAIL_NAME} cp -f /mnt/configs/FreeBSD.conf /usr/local/etc/pkg/repos/FreeBSD.conf

#
# Upgrade to the lastest repo
iocage exec ${JAIL_NAME} pkg upgrade -y
iocage restart ${JAIL_NAME}

#
# remove /mnt/configs as no longer needed
#iocage fstab -r ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0

echo
echo "DB PASSWORD ${DB_PASSWORD}"
echo "Wordpress should be available at http://${JAIL_IP}/index.php"

