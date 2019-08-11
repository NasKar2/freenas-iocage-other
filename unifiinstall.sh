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
UNIFI_DATA=""


SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
. $SCRIPTPATH/unifi-config
CONFIGS_PATH=$SCRIPTPATH/configs
DB_ROOT_PASSWORD=$(openssl rand -base64 16)
DB_PASSWORD=$(openssl rand -base64 16)
ADMIN_PASSWORD=$(openssl rand -base64 12)
RELEASE=$(freebsd-version | sed "s/STABLE/RELEASE/g")

# Check for unifi-config and set configuration
if ! [ -e $SCRIPTPATH/unifi-config ]; then
  echo "$SCRIPTPATH/unifi-config must exist."
  exit 1
fi

# Check that necessary variables were set by unifi-config
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

if [ -z $UNIFI_DATA ]; then
  echo 'Configuration error: UNIFI_DATA must be set'
  exit 1
fi

#
# Create Jail
#echo '{"pkgs":["nano","nginx","php56-xml","php56-hash","php56-gd","php56-curl","php56-tokenizer","php56-zlib","php56-zip","mysql56-server","php56","php56-mysql"]}' > /tmp/pkg.json
echo '{"pkgs":["nano","bash","llvm40","openjdk8","unifi5"]}' > /tmp/pkg.json
echo $RELEASE
if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" ip4_addr="${INTERFACE}|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}"
then
	echo "Failed to create jail"
	exit 1
fi
rm /tmp/pkg.json

# fix 'libdl.so.1 missing' error in 11.1 versions, by reinstalling packages from older FreeBSD release
# source: https://forums.freenas.org/index.php?threads/openvpn-fails-in-jail-with-libdl-so-1-not-found-error.70391/
#if [ "${RELEASE}" = "11.1-RELEASE" ]; then
#  iocage exec ${JAIL_NAME} sed -i '' "s/quarterly/release_2/" /etc/pkg/FreeBSD.conf
#  iocage exec ${JAIL_NAME} pkg update -f
#  iocage exec ${JAIL_NAME} pkg upgrade -yf
#fi

iocage exec ${JAIL_NAME} sysrc unifi_enable="YES"
iocage exec ${JAIL_NAME} service unifi start

#exit
#
# needed for installing from ports
#mkdir -p ${PORTS_PATH}/ports
#mkdir -p ${PORTS_PATH}/db

mkdir -p ${POOL_PATH}/${APPS_PATH}/${UNIFI_DATA}
echo "mkdir -p '${POOL_PATH}/${APPS_PATH}/${UNIFI_DATA}'"

unifi_config=${POOL_PATH}/${APPS_PATH}/${UNIFI_DATA}
iocage exec ${JAIL_NAME} 'sysrc ifconfig_epair0_name="epair0b"'

#
# mount ports so they can be accessed in the jail
#iocage fstab -a ${JAIL_NAME} ${PORTS_PATH}/ports /usr/ports nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${PORTS_PATH}/db /var/db/portsnap nullfs rw 0 0

iocage fstab -a ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${unifi_config} /config nullfs rw 0 0

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

echo "Unifi should be available at https://${JAIL_IP}:8443"

