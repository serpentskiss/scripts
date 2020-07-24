#!/usr/bin/env bash

# ############################################################################# #
# UBUNTU SERVER 20 LTS LAMP SERVER INSTALLATION SCRIPT                          #
# ############################################################################# #
# Version       : 1.01.003                                                      #
# Released      : 07 Jul 2020                                                   #
# Last Updated  : 10 Jul 2020                                                   #
# Author        : Jon Thompson <jon@jonthompson.co.uk>                          #
# ############################################################################# #
# UPDATE HISTORY                                                                #
#                                                                               #
#   v1.01.003   : 10 Jul 2020                                                   #
#                 Updated `apt-get -qq` to `apt-get -y`                         #
#                 Updated PHP version to 7.4                                    #
#                 Fixed usermod syntax error                                    #
#                 Fixed Apache base homeDir creation                            #
#                 Fixed erroneous backslashes in vhost block                    #
#                 Fixed password-hashing for new user creation                  #
#                                                                               #
#   v1.01.002   : 09 Jul 2020                                                   #
#                 Added PHP-MySQL extension                                     #
#                                                                               #
#   v1.01.001   : 07 Jul 2020                                                   #
#                 Initial release                                               #
# ############################################################################# #


set -o errexit
set -o nounset


# ============================================================================= #
# Script needs to be run as root, as it deals with protected files and services #
# ============================================================================= #
USER=`whoami`

if [[ ! ${USER} = 'root' ]]; then
    echo " + ERROR";
    echo " + Please run this script with root privileges";
    echo " "
    exit 1;
fi

# ============================================================================= #
# Variables                                                                     #
# ============================================================================= #
MYSQLROOTPWD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
WEBUSERPWD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
SALT=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
WEBUSERPWDHASH=$(openssl passwd -6 -salt ${SALT} ${WEBUSERPWD})
IPADDRESS=$(ip addr show eth0 | grep -oE 'inet [0-9.]+' | cut -d ' ' -f 2)


# ============================================================================= #
# Save login information                                                        #
# ============================================================================= #
cat << _EOF_ >> ~/LOGIN

+-------------------------------------------------------------------------------+
| SERVER AND LOGIN INFORMATION                                                  |
+-------------------------------------------------------------------------------+

IP ADDRESS    : ${IPADDRESS}
TEST SITE     : http://${IPADDRESS}
FTP USER      : webuser:${WEBUSERPWD}
MYSQL ROOT    : root:${MYSQLROOTPWD}

_EOF_

# ============================================================================= #
# Run an update first
# ============================================================================= #
apt-get -y update 2>&1
apt-get -y --with-new-pkgs upgrade 2>&1

# ============================================================================= #
# Install all our binaries                                                      #
# ============================================================================= #
apt-get -y install apache2 2>&1
apt-get -y install php7.4 php7.4-cli php7.4-gd php7.4-imap php7.4-mbstring php7.4-mysql php7.4-xml php-pear php-xdebug 2>&1
phpenmod pdo_mysql 2>&1
apt-get install -y mariadb-server mariadb-client 2>&1
apt-get install -y ffmpeg zip unzip jpegoptim optipng mcrypt 2>&1
curl --silent -L https://yt-dl.org/downloads/latest/youtube-dl -o /usr/local/bin/youtube-dl 2>&1
chmod a+rx /usr/local/bin/youtube-dl

# ============================================================================= #
# Add a new SFTP user to upload files to the sites                              #
# ============================================================================= #
addgroup sftpusers
useradd -g sftpusers -s /sbin/nologin -d /var/www/sites -p ${WEBUSERPWDHASH} webuser
usermod -aG sudo webuser
chown root: /var/www
mkdir -p /var/www/sites
chown webuser:sftpusers /var/www/sites
sed -i 's/Subsystem sftp/# Subsystem sftp/' /etc/ssh/sshd_config

cat << _EOF_ >> /etc/ssh/sshd_config


Subsystem sftp internal-sftp
Match Group sftpusers
ForceCommand internal-sftp
ChrootDirectory /var/www
X11Forwarding no
AllowTcpForwarding no
_EOF_

systemctl restart sshd

# ============================================================================= #
# Enable & configure mod_vhost_alias, set Apache to run as our SFTP user        #
# ============================================================================= #
a2enmod vhost_alias
sed -i 's/export APACHE_RUN_USER=www-data/export APACHE_RUN_USER=webuser/' /etc/apache2/envvars
sed -i 's/export APACHE_RUN_GROUP=www-data/export APACHE_RUN_GROUP=sftpusers/' /etc/apache2/envvars
sed -i 's/#Mutex file:\${APACHE_LOCK_DIR} default/Mutex file:\${APACHE_LOCK_DIR} default\nMutex flock/' /etc/apache2/apache2.conf

cat << _EOF_ > /etc/apache2/sites-available/000-default.conf
<VirtualHost *:80>
        ServerAdmin webmaster@localhost
        VirtualDocumentRoot /var/www/sites/%0/web
        ErrorLog \${APACHE_LOG_DIR}/error.log
        CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>

<Directory /var/www/sites>
    Options Indexes FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

# vim: syntax=apache ts=4 sw=4 sts=4 sr noet
_EOF_

# ============================================================================= #
# Create a default site that will show phpinfo()                                #
# ============================================================================= #
mkdir -p /var/www/sites/${IPADDRESS}/web

cat << _EOF_ > /var/www/sites/${IPADDRESS}/web/index.php
<?php
phpinfo();
_EOF_

chown -R webuser:sftpusers /var/www/sites
find /var/www/sites -type d -exec chmod 0755 {} \;
find /var/www/sites -type f -exec chmod 0644 {} \;

# ============================================================================= #
# Configure php.ini                                                             #
# ============================================================================= #
PHPINI=`php -i | grep 'Loaded Configuration File' | cut -d '>' -f 2 | cut -d ' ' -f 2 | sed 's/cli/apache2/'`
sed -i 's/max_execution_time = 30/max_execution_time = 90/' ${PHPINI}
sed -i 's/post_max_size = 8M/post_max_size = 64M/' ${PHPINI}
sed -i 's/upload_max_filesize = 2M//' ${PHPINI}
sed -i 's/allow_url_fopen = On/allow_url_fopen = Off/' ${PHPINI}
sed -i 's/;date.timezone =/date.timezone = Europe\/London/' ${PHPINI}
sed -i 's/mail.add_x_header = Off/mail.add_x_header = On/' ${PHPINI}
systemctl restart apache2

# ============================================================================= #
# Secure MySQL using options found in mysql_secure_installation                 #
# ============================================================================= #
mysql --user=root <<_EOF_
  UPDATE mysql.user SET Password=PASSWORD('${MYSQLROOTPWD}') WHERE User='root';
  DELETE FROM mysql.user WHERE User='';
  DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
  DROP DATABASE IF EXISTS test;
  DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
  FLUSH PRIVILEGES;
_EOF_


# ============================================================================= #
# Display login information once complete                                       #
# ============================================================================= #
echo " "
echo " +-------------------------------------------------------------------------+"
echo " | SERVER AND LOGIN INFORMATION                                            |"
echo " +-------------------------------------------------------------------------+"
echo " "
echo " IP ADDRESS    : ${IPADDRESS}"
echo " TEST SITE     : http://${IPADDRESS}"
echo " FTP USER      : webuser:${WEBUSERPWD}"
echo " MYSQL ROOT    : root:${MYSQLROOTPWD}"
