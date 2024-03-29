#!/bin/sh
# Build an iocage jail under FreeNAS 12.1 with  prowlarr
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
PROWLARR_DATA=""
USE_BASEJAIL="-b"


SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
. $SCRIPTPATH/prowlarr-config
CONFIGS_PATH=$SCRIPTPATH/configs
DB_ROOT_PASSWORD=$(openssl rand -base64 16)
DB_PASSWORD=$(openssl rand -base64 16)
ADMIN_PASSWORD=$(openssl rand -base64 12)
RELEASE=$(freebsd-version | cut -d - -f -1)"-RELEASE"

# Check for prowlarr-config and set configuration
if ! [ -e $SCRIPTPATH/prowlarr-config ]; then
  echo "$SCRIPTPATH/prowlarr-config must exist."
  exit 1
fi

# Check that necessary variables were set by prowlarr-config
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
  JAIL_NAME="prowlarr"
  echo "JAIL_NAME defaulting to 'prowlarr'"
fi
if [ -z $PROWLARR_DATA ]; then
  PROWLARR_DATA="prowlarr"
  echo "PROWLARR_DATA defaulting to 'prowlarr'"
fi

#
# Create Jail

#echo '{"pkgs":["nano","libunwind","icu","libinotify","openssl","sqlite3","libiconv","mediainfo","curl","ca_root_nss"]}' > /tmp/pkg.json
echo '{"pkgs":["nano","prowlarr"]}' > /tmp/pkg.json
if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" ip4_addr="${INTERFACE}|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}" allow_raw_sockets=1 allow_mlock=1 ${USE_BASEJAIL}
then
	echo "Failed to create jail"
	exit 1
fi
rm /tmp/pkg.json

#
# needed for installing from ports
#mkdir -p ${PORTS_PATH}/ports
#mkdir -p ${PORTS_PATH}/db

mkdir -p ${POOL_PATH}/${APPS_PATH}/${PROWLARR_DATA}
echo "mkdir -p '${POOL_PATH}/${APPS_PATH}/${PROWLARR_DATA}'"

prowlarr_config=${POOL_PATH}/${APPS_PATH}/${PROWLARR_DATA}
#iocage exec ${JAIL_NAME} 'sysrc ifconfig_epair0_name="epair0b"'

# create dir in jail for mount points
#iocage exec ${JAIL_NAME} mkdir -p /usr/ports
#iocage exec ${JAIL_NAME} mkdir -p /var/db/portsnap
iocage exec ${JAIL_NAME} mkdir -p /config
iocage exec ${JAIL_NAME} mkdir -p /mnt/configs

#
# mount ports so they can be accessed in the jail
#iocage fstab -a ${JAIL_NAME} ${PORTS_PATH}/ports /usr/ports nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${PORTS_PATH}/db /var/db/portsnap nullfs rw 0 0

iocage fstab -a ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${prowlarr_config} /config nullfs rw 0 0

iocage exec ${JAIL_NAME} sysrc prowlarr_enable=TRUE
iocage exec ${JAIL_NAME} sysrc prowlarr_data_dir="/config"
iocage exec ${JAIL_NAME} service prowlarr start

#iocage exec ${JAIL_NAME} chown -R prowlarr:prowlarr /usr/local/share/Prowlarr /config
#iocage exec ${JAIL_NAME} "mkdir -p /usr/local/etc/rc.d"
#iocage exec ${JAIL_NAME} cp -f /mnt/configs/prowlarr /usr/local/etc/rc.d/prowlarr

iocage exec ${JAIL_NAME} chmod u+x /usr/local/etc/rc.d/prowlarr
iocage exec ${JAIL_NAME} sysrc "prowlarr_enable=YES"
iocage exec ${JAIL_NAME} sysrc "prowlarr_data_dir=/config"
#iocage exec ${JAIL_NAME} chown -R prowlarr:prowlarr /usr/local/etc/rc.d/prowlarr
iocage exec ${JAIL_NAME} service prowlarr restart

iocage restart ${JAIL_NAME}
 
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

echo "prowlarr should be available at http://${JAIL_IP}:9696"

