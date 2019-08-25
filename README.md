# freenas-iocage-other

#### https://github.com/NasKar2/freenas-iocage-other.git

Scripts to create an iocage jail on Freenas 11.1U4 from scratch in separate jails for Unifi, Emby, Wordpress, Jackett, UrBackup, Transmission, Handbrake, LazyLibrarian and Backup/Restore Wordpress

Unifi etc. will be placed in a jail with separate data directory (/mnt/v1/apps/...) to allow for easy reinstallation/backup.

The Emby user is emby:emby and the user media added to jail.  emby is added to the media group

LazyLibrarian added config file in jail at /usr/local/share/lazylibrarian/config.ini

### Prerequisites
Edit file unifi-config

Edit unifi-config file with the name of your jail, your network information and directory data name you want to use and location of your media files and torrents.

UNIFI_DATA= will create a data directory /mnt/v1/apps/unifi to store all the data for that app.

MEDIA_LOCATION will set the location of your media files, in this example /mnt/v1/media


```
JAIL_IP="192.168.5.239"
DEFAULT_GW_IP="192.168.5.1"
INTERFACE="igb0"
VNET="off"
POOL_PATH="/mnt/v1"
APPS_PATH="apps"
JAIL_NAME="unifi"
UNIFI_DATA="unifi"
MEDIA_LOCATION="media"
```

Likewise create config files for the other apps - emby-config, jackett-config urbackup-config, handbrake-config and replace JAIL_IP, JAIL_NAME, and JAIL_DATA with the name of the application. For example see below for emby.

```
JAIL_IP="192.168.5.238"
DEFAULT_GW_IP="192.168.5.1"
INTERFACE="igb0"
VNET="off"
JAIL_NAME="emby"
POOL_PATH="/mnt/v1"
APPS_PATH="apps"
EMBY_DATA="emby"
MEDIA_LOCATION="media"
TORRENTS_LOCATION="torrents"
```

Create wp-config for Wordpress add the field to choose the DB_PASSWORD or have it randomly generated if blank.

```
JAIL_IP="192.168.5.237"
DEFAULT_GW_IP="192.168.5.1"
INTERFACE="em0"
VNET="off"
POOL_PATH="/mnt/v1"
APPS_PATH="apps"
JAIL_NAME="wordpress"
WP_DATA="wordpress"
DB_PASSWORD="yourdatabasepassword"
```

Create WordpressBackup-config. Can backup wordpress files and wordpress database to /mnt/v1/backup/wpbackup.tar.gz.  Restore will replace all the wordpress files and restore the database.  If cron="yes" then it will default to backup to allow it to be called by a cronjob.

```
cron=""
POOL_PATH="/mnt/v1"
APPS_PATH="apps"
CONFIG_PATH="config"
JAIL_NAME="wordpress"
WP_SOURCE="wordpress"
WP_DESTINATION="wpbackup"
BACKUP_PATH="backup"
BACKUP_NAME="wpbackup.tar.gz"
DATABASE_NAME="wordpress"
DB_BACKUP_NAME="wordpress.sql"
DB_PASSWORD="yourdatabasepassword"
```

Create urbackup-config.

```
JAIL_IP="192.168.5.243"
DEFAULT_GW_IP="192.168.5.1"
INTERFACE="em0"
VNET="off"
POOL_PATH="/mnt/v1"
APPS_PATH="apps"
JAIL_NAME="urbackup"
URBACKUP_DATA="urbackup"
```

Create lazylib-config.

```
JAIL_IP="192.168.5.254"
DEFAULT_GW_IP="192.168.5.1"
INTERFACE="em0"
VNET="off"
JAIL_NAME="lazylib"
POOL_PATH="/mnt/v1"
APPS_PATH="apps"
LAZYLIB_DATA="lazylib"
MEDIA_LOCATION="media"
TORRENTS_LOCATION="torrents"
```
## Install Transmission in fresh Jail
Will install as user transmission and the script will change it to media

The script will add in this example 192.168.5.* to the rpc-whitelist so transmission can be accessed from your network.

If your changes more that just the last octet: After stopping the service transmission you will have to manually edit the setting.json file in the config folder.

Create transmission-config.
```
JAIL_IP="192.168.5.76"
DEFAULT_GW_IP="192.168.5.1"
INTERFACE="vnet0"
VNET="on"
JAIL_NAME="transmission"
POOL_PATH="/mnt/v1"
APPS_PATH="apps"
TRANSMISSION_DATA="transmission"
TORRENTS_LOCATION="torrents"
```
Create openvpn.conf and pass.txt files in config directory. Example files shown, you have to edit the details
```
client
dev tun
proto udp
remote vpnaddress.com 1194
resolv-retry infinite
nobind
persist-key
persist-tun
persist-remote-ip
ca vpn.crt

tls-client
remote-cert-tls server
#auth-user-pass
auth-user-pass /config/pass.txt
comp-lzo
verb 3

auth SHA256
cipher AES-256-CBC

<ca>
-----BEGIN CERTIFICATE-----
MIIESDC...............
-----END CERTIFICATE-----
</ca>

```
pass.txt
```
vpn_username
vpn_password
```

## Install Unifi in fresh Jail

Create an iocage jail to install Unifi.

Then run this command to install Unifi
```
./unifiinstall.sh
```

## Install Lazylibrarian in fresh jail

create lazylib-config as referenced above

Run the script ./lazylibinstall.sh

After install follow directions between the red stars

go into jail and execute these commands
```
iocage console ${JAIL_NAME}
cd /urllib3
python setup.py install
exit 
```

Other apps can be installed with ./AppNameinstall.sh

## After install

After install of UrBackup go to Settings/General/Server/Backup storage path: /config
