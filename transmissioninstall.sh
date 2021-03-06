#!/bin/sh
# Build an iocage jail under FreeNAS 11.2 with  Transmission
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
JAIL_NAME=""
POOL_PATH=""
APPS_PATH=""
TRANSMISSION_DATA=""
TORRENTS_LOCATION=""
USE_BASEJAIL="-b"

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
. $SCRIPTPATH/transmission-config
CONFIGS_PATH=$SCRIPTPATH/configs
DB_ROOT_PASSWORD=$(openssl rand -base64 16)
DB_PASSWORD=$(openssl rand -base64 16)
ADMIN_PASSWORD=$(openssl rand -base64 12)
RELEASE=$(freebsd-version | cut -d - -f -1)"-RELEASE"

# Check for transmission-config and set configuration
if ! [ -e $SCRIPTPATH/transmission-config ]; then
  echo "$SCRIPTPATH/transmission-config must exist."
  exit 1
fi

# Check that necessary variables were set by transmission-config
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
  JAIL_NAME="transmission"
  echo "JAIL_NAME defaulting to 'transmission'"
fi
if [ -z $TRANSMISSION_DATA ]; then
  TRANSMISSION_DATA="transmission"
  echo "TRANSMISSION_DATA defaulting to 'transmission'"
fi

if [ -z $TORRENTS_LOCATION ]; then
  TORRENTS_LOCATION="torrents"
  echo "TORRENTS_LOCATION defaulting to 'torrents'"
fi

#
# Create Jail
echo '{"pkgs":["nano","bash","unzip","unrar","transmission","openvpn","ca_root_nss"]}' > /tmp/pkg.json
if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" ip4_addr="${INTERFACE}|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}" allow_raw_sockets="1" allow_tun="1" ${USE_BASEJAIL}
then
	echo "Failed to create jail"
	exit 1
fi
rm /tmp/pkg.json

transmission_config=${POOL_PATH}/${APPS_PATH}/${TRANSMISSION_DATA}
mkdir -p ${POOL_PATH}/${APPS_PATH}/${TRANSMISSION_DATA}
#echo "mkdir -p ${POOL_PATH}/${APPS_PATH}/${TRANSMISSION_DATA}"

# create torrent dir in base freenas
mkdir -p "${POOL_PATH}/torrents"

# create dir in jail for mount points
iocage exec ${JAIL_NAME} mkdir -p /usr/ports
iocage exec ${JAIL_NAME} mkdir -p /var/db/portsnap
iocage exec ${JAIL_NAME} mkdir -p /config
iocage exec ${JAIL_NAME} mkdir -p /mnt/configs
iocage exec ${JAIL_NAME} mkdir -p /mnt/torrents

iocage fstab -a ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0
# echo ${transmission_config}
iocage fstab -a ${JAIL_NAME} ${transmission_config} /config nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/${TORRENTS_LOCATION} /mnt/torrents nullfs rw 0 0

#iocage exec ${JAIL_NAME} "pw user add media -c media -u 8675309  -d /nonexistent -s /usr/bin/nologin"

iocage exec ${JAIL_NAME} 'sysrc ifconfig_epair0_name="epair0b"'

iocage exec ${JAIL_NAME} mkdir -p /config/transmission-home
iocage exec ${JAIL_NAME} chown -R transmission:transmission /config /mnt/torrents
#iocage exec ${JAIL_NAME} 'ifconfig tun create'
# ipfw_rules
iocage exec ${JAIL_NAME} cp -f /mnt/configs/ipfw_rules /config/ipfw_rules

# openvpn.conf
iocage exec ${JAIL_NAME} cp -f /mnt/configs/openvpn.conf /config/openvpn.conf
iocage exec ${JAIL_NAME} cp -f /mnt/configs/pass.txt /config/pass.txt

iocage exec ${JAIL_NAME} "chown 0:0 /config/ipfw_rules"
iocage exec ${JAIL_NAME} "chmod 600 /config/ipfw_rules"
iocage exec ${JAIL_NAME} sysrc "firewall_enable=YES"
iocage exec ${JAIL_NAME} sysrc "firewall_script=/config/ipfw_rules"
iocage exec ${JAIL_NAME} sysrc "openvpn_enable=YES"
iocage exec ${JAIL_NAME} sysrc "openvpn_dir=/config"
iocage exec ${JAIL_NAME} sysrc "openvpn_configfile=/config/openvpn.conf"
iocage exec ${JAIL_NAME} sysrc "transmission_enable=YES"
iocage exec ${JAIL_NAME} sysrc "transmission_conf_dir=/config/transmission-home"
iocage exec ${JAIL_NAME} sysrc "transmission_download_dir=/mnt/torrents/completed"
#iocage exec ${JAIL_NAME} 'ifconfig tun create'
#TUN_NUM=$(iocage exec ${JAIL_NAME} ifconfig | grep tun | cut -d : -f1 | grep tun)
#echo "TUN_NUM is ${TUN_NUM}"
iocage exec ${JAIL_NAME} service transmission start

iocage exec ${JAIL_NAME} service transmission stop
baseip=`echo $JAIL_IP | cut -d"." -f1-3`
iocage exec ${JAIL_NAME} sed -i '' "s/\"rpc-whitelist\": \"127.0.0.1\",/\"rpc-whitelist\": \"$baseip\.*\",/" /config/transmission-home/settings.json
#iocage exec ${JAIL_NAME} sed -i '' 's/\"rpc-whitelist-enabled": \true/\"rpc-whitelist-enabled": \false/g' /config/transmission-home/settings.json

# Change user to media
iocage exec ${JAIL_NAME} "pw user add media -c media -u 8675309  -d /nonexistent -s /usr/bin/nologin"
iocage exec ${JAIL_NAME} "pw groupmod media -m transmission"
iocage exec ${JAIL_NAME} "pw groupmod transmission -m media"
#iocage exec ${JAIL_NAME} sed -i '' "s/transmission_user=\"transmission\"/transmission_user=\"media\"/" /usr/local/etc/rc.d/transmission
iocage exec ${JAIL_NAME} sed -i '' "s/transmission_user:=transmission/transmission_user:=media/g" /usr/local/etc/rc.d/transmission
iocage exec ${JAIL_NAME} chown -R media:media /config /usr/local/etc/rc.d/transmission /mnt/torrents
iocage exec ${JAIL_NAME} sysrc transmission_user="media"
iocage exec ${JAIL_NAME} sysrc transmission_group="media"
iocage exec ${JAIL_NAME} 'ifconfig tun create'
TUN_NUM=$(iocage exec ${JAIL_NAME} ifconfig | grep tun | cut -d : -f1 | grep tun)
echo "TUN_NUM is ${TUN_NUM}"
iocage exec ${JAIL_NAME} sed -i '' "s|mytun|${TUN_NUM}|" /config/ipfw_rules
iocage exec ${JAIL_NAME} sed -i '' "s|dev\ tun|dev\ ${TUN_NUM}|" /config/openvpn.conf
iocage exec ${JAIL_NAME} service openvpn start
iocage exec ${JAIL_NAME} service ipfw start
iocage exec ${JAIL_NAME} service transmission start


# fix 'libdl.so.1 missing' error in 11.1 versions, by reinstalling packages from older FreeBSD release
# source: https://forums.freenas.org/index.php?threads/openvpn-fails-in-jail-with-libdl-so-1-not-found-error.70391/
if [ "${RELEASE}" = "11.1-RELEASE" ]; then
  iocage exec ${JAIL_NAME} sed -i '' "s/quarterly/release_2/" /etc/pkg/FreeBSD.conf
  iocage exec ${JAIL_NAME} pkg update -f
  iocage exec ${JAIL_NAME} pkg upgrade -yf
fi

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

echo "Transmission should be available at http://${JAIL_IP}:9091/transmission/web/"
echo
echo "Must have trailing / or will get an Session-ID error"

