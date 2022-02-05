#!/bin/sh
# Build an iocage jail under FreeNAS 12.1 with  Jackett
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
JACKETT_DATA=""
USE_BASEJAIL="-b"


SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
. $SCRIPTPATH/jackett-config
CONFIGS_PATH=$SCRIPTPATH/configs
DB_ROOT_PASSWORD=$(openssl rand -base64 16)
DB_PASSWORD=$(openssl rand -base64 16)
ADMIN_PASSWORD=$(openssl rand -base64 12)
RELEASE=$(freebsd-version | cut -d - -f -1)"-RELEASE"

# Check for jackett-config and set configuration
if ! [ -e $SCRIPTPATH/jackett-config ]; then
  echo "$SCRIPTPATH/jackett-config must exist."
  exit 1
fi

# Check that necessary variables were set by jackett-config
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
  JAIL_NAME="jackett"
  echo "JAIL_NAME defaulting to 'jackett'"
fi
if [ -z $JACKETT_DATA ]; then
  JACKETT_DATA="jackett"
  echo "JACKETT_DATA defaulting to 'jackett'"
fi

#
# Create Jail

echo '{"pkgs":["nano","mono6.8","curl","ca_root_nss"]}' > /tmp/pkg.json
if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" ip4_addr="${INTERFACE}|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}" allow_raw_sockets=1 ${USE_BASEJAIL}
then
	echo "Failed to create jail"
	exit 1
fi
rm /tmp/pkg.json

iocage exec ${JAIL_NAME} sysrc jackett_enable="YES"
iocage exec ${JAIL_NAME} service jackett start

#
# update mono to 6.8.0.105
#iocage exec ${JAIL_NAME} cd /tmp
#iocage exec ${JAIL_NAME} pkg install -y libiconv
#iocage exec ${JAIL_NAME} fetch https://github.com/jailmanager/jailmanager.github.io/releases/download/v0.0.1/mono-6.8.0.105.txz
#iocage exec ${JAIL_NAME} cp /mnt/configs/mono-6.8.0.105.txz /tmp/mono-6.8.0.105.txz
#iocage exec ${JAIL_NAME} pkg install -y /tmp/mono-6.8.0.105.txz
#iocage exec ${JAIL_NAME} rm /tmp/mono-6.8.0.105.txz


#exit
#
# needed for installing from ports
#mkdir -p ${PORTS_PATH}/ports
#mkdir -p ${PORTS_PATH}/db

mkdir -p ${POOL_PATH}/${APPS_PATH}/${JACKETT_DATA}
echo "mkdir -p '${POOL_PATH}/${APPS_PATH}/${JACKETT_DATA}'"

jackett_config=${POOL_PATH}/${APPS_PATH}/${JACKETT_DATA}
iocage exec ${JAIL_NAME} 'sysrc ifconfig_epair0_name="epair0b"'

# create dir in jail for mount points
iocage exec ${JAIL_NAME} mkdir -p /usr/ports
iocage exec ${JAIL_NAME} mkdir -p /var/db/portsnap
iocage exec ${JAIL_NAME} mkdir -p /config
iocage exec ${JAIL_NAME} mkdir -p /mnt/configs

#
# mount ports so they can be accessed in the jail
#iocage fstab -a ${JAIL_NAME} ${PORTS_PATH}/ports /usr/ports nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${PORTS_PATH}/db /var/db/portsnap nullfs rw 0 0

iocage fstab -a ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${jackett_config} /config nullfs rw 0 0

iocage exec ${JAIL_NAME} ln -s /usr/local/bin/mono /usr/bin/mono
iocage exec ${JAIL_NAME} "fetch https://github.com/Jackett/Jackett/releases/download/v0.18.875/Jackett.Binaries.Mono.tar.gz -o /usr/local/share"
#iocage exec ${JAIL_NAME} "fetch https://github.com/Jackett/Jackett/releases/download/v0.9.16/Jackett.Binaries.Mono.tar.gz -o /usr/local/share"
iocage exec ${JAIL_NAME} "tar -xzvf /usr/local/share/Jackett.Binaries.Mono.tar.gz -C /usr/local/share"
iocage exec ${JAIL_NAME} rm /usr/local/share/Jackett.Binaries.Mono.tar.gz
iocage exec ${JAIL_NAME} "pw user add jackett -c jackett -u 818 -d /nonexistent -s /usr/bin/nologin"
iocage exec ${JAIL_NAME} chown -R jackett:jackett /usr/local/share/Jackett /config
iocage exec ${JAIL_NAME} mkdir /usr/local/etc/rc.d
iocage exec ${JAIL_NAME} cp -f /mnt/configs/jackett /usr/local/etc/rc.d/jackett

iocage exec ${JAIL_NAME} chmod u+x /usr/local/etc/rc.d/jackett
iocage exec ${JAIL_NAME} sysrc "jackett_enable=YES"
iocage exec ${JAIL_NAME} service jackett restart

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

echo "Jackett should be available at http://${JAIL_IP}:9117"

