#!/bin/sh
# Build an iocage jail under FreeNAS 11.2 with  Jellyfin
# https://github.com/NasKar2/freenas-iocage-other

# Check for root privileges
if ! [ $(id -u) = 0 ]; then
   echo "This script must be run with root privileges"
   exit 1
fi

# Initialize defaults
JAIL_IP=""
DEFAULT_GW_IP=""
INTERFACE=""
VNET=""
POOL_PATH=""
APPS_PATH=""
JELLYFIN_DATA=""
MEDIA_LOCATION=""
USE_BASEJAIL="-b"

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
. $SCRIPTPATH/jellyfin-config
CONFIGS_PATH=$SCRIPTPATH/configs
DB_ROOT_PASSWORD=$(openssl rand -base64 16)
DB_PASSWORD=$(openssl rand -base64 16)
ADMIN_PASSWORD=$(openssl rand -base64 12)
RELEASE=$(freebsd-version | cut -d - -f -1)"-RELEASE"
echo "RELEASE=${RELEASE}"
# Check for jellyfin-config and set configuration
if ! [ -e $SCRIPTPATH/jellyfin-config ]; then
  echo "$SCRIPTPATH/jellyfin-config must exist."
  exit 1
fi

# Check that necessary variables were set by jellyfin-config
if [ -z $JAIL_IP ]; then
  echo 'Configuration error: JAIL_IP must be set'
  exit 1
fi
if [ -z $DEFAULT_GW_IP ]; then
  echo 'Configuration error: DEFAULT_GW_IP must be set'
  exit 1
fi
if [ -z $INTERFACE ]; then
  INTERFACE="vnet0"
  echo "INTERFACE defaulting to 'vnet0'"
fi
if [ -z $VNET ]; then
  VNET="on"
  echo "VNET defaulting to 'on'"
fi

if [ -z $POOL_PATH ]; then
  POOL_PATH="/mnt/$(iocage get -p)"
  echo "POOL_PATH defaulting to "$POOL_PATH
fi
if [ -z $APPS_PATH ]; then
  APPS_PATH="apps"
  echo "APPS_PATH defaulting to 'apps'"
fi

if [ -z $JAIL_NAME ]; then
  JAIL_NAME="jellyfin"
  echo "JAIL_NAME defaulting to 'jellyfin'"
fi
if [ -z $JELLYFIN_DATA ]; then
  JELLYFIN_DATA="jellyfin"
  echo "JELLYFIN_DATA defaulting to 'jellyfin'"
fi
if [ -z $MEDIA_LOCATION ]; then
  MEDIA_LOCATION="media"
  echo "MEDIA_LOCATION defaulting to 'media'"
fi

#
# Create Jail
#wget https://raw.githubusercontent.com/MediaBrowser/iocage-amd64/master/Jellyfin-server.json

echo '{"pkgs":["nano"]}' > /tmp/pkg.json
if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" ip4_addr="${INTERFACE}|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}" ${USE_BASEJAIL} allow_raw_sockets=1 allow_mlock=1
then
	echo "Failed to create jail"
	exit 1
fi
rm /tmp/pkg.json
iocage exec ${JAIL_NAME} fetch https://github.com/Thefrank/jellyfin-server-freebsd/releases/download/v10.8.4/jellyfinserver-10.8.4.pkg
iocage exec ${JAIL_NAME} pkg install -y jellyfinserver-10.8.4.pkg
iocage exec ${JAIL_NAME} rm jellyfinserver-10.8.4.pkg

iocage exec ${JAIL_NAME} "pw user add media -c media -u 8675309  -d /nonexistent -s /usr/bin/nologin"
iocage exec ${JAIL_NAME} sysrc jellyfinserver_enable=TRUE
iocage exec ${JAIL_NAME} service jellyfinserver start
iocage exec ${JAIL_NAME} service jellyfinserver stop
iocage exec ${JAIL_NAME} sysrc jellyfinserver_user=media
iocage exec ${JAIL_NAME} sysrc jellyfinserver_group=media
iocage exec ${JAIL_NAME} sysrc jellyfinserver_data_dir=/config
mkdir -p ${POOL_PATH}/${APPS_PATH}/${JELLYFIN_DATA}
mkdir -p ${POOL_PATH}/${MEDIA_LOCATION}
echo "mkdir -p '${POOL_PATH}/${APPS_PATH}/${JELLYFIN_DATA}'"

jellyfin_config=${POOL_PATH}/${APPS_PATH}/${JELLYFIN_DATA}
#iocage exec ${JAIL_NAME} 'sysrc ifconfig_epair0_name="epair0b"'

# create dir in jail for mount points
iocage exec ${JAIL_NAME} mkdir -p /config
iocage exec ${JAIL_NAME} mkdir -p /mnt/media
iocage exec ${JAIL_NAME} mkdir -p /mnt/configs

#service jellyfinserver start

# mount ports so they can be accessed in the jail
iocage fstab -a ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${jellyfin_config} /config nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/${MEDIA_LOCATION} /mnt/media nullfs rw 0 0

#service jellyfinserver start
#iocage exec ${JAIL_NAME} "chown -R media:media /var/cache/jellyfinserver/ /var/db/jellyfinserver/ /usr/local/jellyfinserver/ /usr/local/etc/rc.d/jellyfinserver /config"
iocage exec ${JAIL_NAME} "chown -R media:media /usr/local/jellyfinserver/ /usr/local/etc/rc.d/jellyfinserver /config /var/cache/jellyfinserver/"

iocage exec ${JAIL_NAME} service jellyfinserver start
echo "Jellyfin installed"
echo "Jellyfin can be found at http://${JAIL_IP}:8096"

exit

# fix 'libdl.so.1 missing' error in 11.1 versions, by reinstalling packages from older FreeBSD release
# source: https://forums.freenas.org/index.php?threads/openvpn-fails-in-jail-with-libdl-so-1-not-found-error.70391/
if [ "${RELEASE}" = "11.1-RELEASE" ]; then
  iocage exec ${JAIL_NAME} sed -i '' "s/quarterly/release_2/" /etc/pkg/FreeBSD.conf
  iocage exec ${JAIL_NAME} pkg update -f
  iocage exec ${JAIL_NAME} pkg upgrade -yf
fi

#
# needed for installing from ports
#mkdir -p ${PORTS_PATH}/ports
#mkdir -p ${PORTS_PATH}/db

mkdir -p ${POOL_PATH}/${APPS_PATH}/${JELLYFIN_DATA}
mkdir -p ${POOL_PATH}/${MEDIA_LOCATION}
mkdir -p ${POOL_PATH}/${TORRENTS_LOCATION}
echo "mkdir -p '${POOL_PATH}/${APPS_PATH}/${JELLYFIN_DATA}'"

jellyfin_config=${POOL_PATH}/${APPS_PATH}/${JELLYFIN_DATA}
iocage exec ${JAIL_NAME} 'sysrc ifconfig_epair0_name="epair0b"'

# create dir in jail for mount points
iocage exec ${JAIL_NAME} mkdir -p /usr/ports
iocage exec ${JAIL_NAME} mkdir -p /var/db/portsnap
iocage exec ${JAIL_NAME} mkdir -p /config
iocage exec ${JAIL_NAME} mkdir -p /mnt/media
iocage exec ${JAIL_NAME} mkdir -p /mnt/configs


# mount ports so they can be accessed in the jail
iocage fstab -a ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${jellyfin_config} /config nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/${MEDIA_LOCATION} /mnt/media nullfs rw 0 0

#exit  

#iocage exec ${JAIL_NAME} "pw user add media -c media -u 8675309  -d /nonexistent -s /usr/bin/nologin"
#iocage exec ${JAIL_NAME} chown -R media:media /usr/local/share/jellyfin /config
iocage exec ${JAIL_NAME} "pw user add media -c media -u 8675309  -d /nonexistent -s /usr/bin/nologin"
iocage exec ${JAIL_NAME} "pw groupmod media -m jellyfin"
iocage exec ${JAIL_NAME} "chown -R jellyfin:jellyfin /usr/local/share/jellyfin /config"


#iocage exec ${JAIL_NAME} -- mkdir /usr/local/etc/rc.d
#iocage exec ${JAIL_NAME} cp -f /mnt/configs/jellyfin-server /usr/local/etc/rc.d/jellyfin-server
iocage exec ${JAIL_NAME} chmod u+x /usr/local/etc/rc.d/jellyfin-server
#iocage exec ${JAIL_NAME} sed -i '' "s/jellyfindata/${JELLYFIN_DATA}/" /usr/local/etc/rc.d/sonarr
iocage exec ${JAIL_NAME} sysrc jellyfin_server_enable="YES"
iocage exec ${JAIL_NAME} service jellyfin-server start

iocage restart ${JAIL_NAME}
echo "Jellyfin installed"
echo "Jellyfin can be found at http://${JAIL_IP}:8096"
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

echo "Jellyfin should be available at http://${JAIL_IP}:8096"

