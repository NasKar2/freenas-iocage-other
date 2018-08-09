#!/bin/sh
# Build an iocage jail under FreeNAS 11.1 with  Emby
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
EMBY_DATA=""
MEDIA_LOCATION=""
TORRENTS_LOCATION=""


SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
. $SCRIPTPATH/emby-config
CONFIGS_PATH=$SCRIPTPATH/configs
DB_ROOT_PASSWORD=$(openssl rand -base64 16)
DB_PASSWORD=$(openssl rand -base64 16)
ADMIN_PASSWORD=$(openssl rand -base64 12)


# Check for emby-config and set configuration
if ! [ -e $SCRIPTPATH/emby-config ]; then
  echo "$SCRIPTPATH/emby-config must exist."
  exit 1
fi

# Check that necessary variables were set by emby-config
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

if [ -z $EMBY_DATA ]; then
  echo 'Configuration error: EMBY_DATA must be set'
  exit 1
fi

if [ -z $MEDIA_LOCATION ]; then
  echo 'Configuration error: MEDIA_LOCATION must be set'
  exit 1
fi

#
# Create Jail
#wget https://raw.githubusercontent.com/MediaBrowser/iocage-amd64/master/emby-server.json

echo '{"pkgs":["nano","mono","libass","fontconfig","freetype2","fribidi","gnutls","iconv","opus","samba48","sqlite3","libtheora","libva","libvorbis","webp","libx264","libzvbi"]}' > /tmp/pkg.json
iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r 11.1-RELEASE ip4_addr="${INTERFACE}|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}"

#echo '{"pkgs":["nano","mono","libass","fontconfig","freetype2","fribidi","gnutls","iconv","opus"."samba48",sqlite3","libtheora","libva","liborbis","webp","libx264","libvbi"]}' > /tmp/pkg.json
#iocage create --name "${JAIL_NAME}" -p --name emby-server.json ip4_addr="${INTERFACE}|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" 
#iocage create --name "${JAIL_NAME}" -p --name /tmp/pkg.json -r 11.1-RELEASE ip4_addr="${INTERFACE}|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}" 
#iocage create --name "${JAIL_NAME}" -p emby-server.json -r 11.1-RELEASE ip4_addr="${INTERFACE}|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}"
#host_hostname="${JAIL_NAME}" vnet="${VNET}"
iocage exec ${JAIL_NAME} pkg add https://github.com/MediaBrowser/Emby.Releases/releases/download/3.5.2.0/emby-server-freebsd_3.5.2.0_amd64.txz

rm /tmp/pkg.json

#
# needed for installing from ports
#mkdir -p ${PORTS_PATH}/ports
#mkdir -p ${PORTS_PATH}/db

mkdir -p ${POOL_PATH}/${APPS_PATH}/${EMBY_DATA}
mkdir -p ${POOL_PATH}/${MEDIA_LOCATION}
mkdir -p ${POOL_PATH}/${TORRENTS_LOCATION}
echo "mkdir -p '${POOL_PATH}/${APPS_PATH}/${EMBY_DATA}'"

emby_config=${POOL_PATH}/${APPS_PATH}/${EMBY_DATA}
iocage exec ${JAIL_NAME} 'sysrc ifconfig_epair0_name="epair0b"'

#
# mount ports so they can be accessed in the jail
#iocage fstab -a ${JAIL_NAME} ${PORTS_PATH}/ports /usr/ports nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${PORTS_PATH}/db /var/db/portsnap nullfs rw 0 0

iocage fstab -a ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${emby_config} /config nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/${MEDIA_LOCATION} /mnt/media nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/${TORRENTS_LOCATION} /mnt/torrents nullfs rw 0 0

#exit  

#iocage exec ${JAIL_NAME} "pw user add media -c media -u 8675309  -d /nonexistent -s /usr/bin/nologin"
#iocage exec ${JAIL_NAME} chown -R media:media /usr/local/share/emby /config
iocage exec ${JAIL_NAME} "pw user add media -c media -u 8675309  -d /nonexistent -s /usr/bin/nologin"
iocage exec ${JAIL_NAME} "pw groupmod media -m emby"
iocage exec ${JAIL_NAME} chown -R emby:emby /usr/local/share/emby /config


#iocage exec ${JAIL_NAME} -- mkdir /usr/local/etc/rc.d
#iocage exec ${JAIL_NAME} cp -f /mnt/configs/emby-server /usr/local/etc/rc.d/emby-server
iocage exec ${JAIL_NAME} chmod u+x /usr/local/etc/rc.d/emby-server
#iocage exec ${JAIL_NAME} sed -i '' "s/embydata/${EMBY_DATA}/" /usr/local/etc/rc.d/sonarr
iocage exec ${JAIL_NAME} sysrc emby_server_enable="YES"
iocage exec ${JAIL_NAME} service emby-server start

iocage restart ${JAIL_NAME}
echo "Emby installed"
echo "Emby can be found at http://${JAIL_IP}:8096"
exit

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

#
# Make media owner of data directories
chown -R media:media ${POOL_PATH}/${MEDIA_LOCATION}
chown -R media:media ${POOL_PATH}/${TORRENTS_LOCATION}

echo

echo "Emby should be available at http://${JAIL_IP}:"

