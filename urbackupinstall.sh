#!/bin/sh
# Build an iocage jail under FreeNAS 11.2 with  UrBackup
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
VNET="off"
POOL_PATH=""
APPS_PATH=""
URBACKUP_DATA=""
USE_BASEJAIL="-b"

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
. $SCRIPTPATH/urbackup-config
CONFIGS_PATH=$SCRIPTPATH/configs
DB_ROOT_PASSWORD=$(openssl rand -base64 16)
DB_PASSWORD=$(openssl rand -base64 16)
ADMIN_PASSWORD=$(openssl rand -base64 12)
RELEASE=$(freebsd-version | sed "s/STABLE/RELEASE/g" | sed "s/-p[0-9]*//")

# Check for urbackup-config and set configuration
if ! [ -e $SCRIPTPATH/urbackup-config ]; then
  echo "$SCRIPTPATH/urbackup-config must exist."
  exit 1
fi

# Check that necessary variables were set by urbackup-config
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

if [ -z $URBACKUP_DATA ]; then
  echo 'Configuration error: URBACKUP_DATA must be set'
  exit 1
fi

#
# Create Jail

echo '{"pkgs":["nano","cryptopp","urbackup-server"]}' > /tmp/pkg.json
if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" ip4_addr="${INTERFACE}|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}" ${USE_BASEJAIL}
then
	echo "Failed to create jail"
	exit 1
fi
rm /tmp/pkg.json

#
# needed for installing from ports
#mkdir -p ${PORTS_PATH}/ports
#mkdir -p ${PORTS_PATH}/db

mkdir -p ${POOL_PATH}/${APPS_PATH}/${URBACKUP_DATA}
echo "mkdir -p '${POOL_PATH}/${APPS_PATH}/${URBACKUP_DATA}'"

urbackup_config=${POOL_PATH}/${APPS_PATH}/${URBACKUP_DATA}
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
iocage fstab -a ${JAIL_NAME} ${urbackup_config} /config nullfs rw 0 0

# fix 'libdl.so.1 missing' error in 11.1 versions, by reinstalling packages from older FreeBSD release
# source: https://forums.freenas.org/index.php?threads/openvpn-fails-in-jail-with-libdl-so-1-not-found-error.70391/
if [ "${RELEASE}" = "11.1-RELEASE" ]; then
#  iocage exec ${JAIL_NAME} sed -i '' "s/quarterly/release_2/" /etc/pkg/FreeBSD.conf
#  iocage exec ${JAIL_NAME} pkg update -f
#  iocage exec ${JAIL_NAME} pkg upgrade -yf
#iocage exec ${JAIL_NAME} cp -f /mnt/configs/libdl.so* /usr/lib/
iocage exec ${JAIL_NAME} cp -f /mnt/configs/libdl.so* /usr/lib/
fi

#
# Install UrBackup

iocage exec ${JAIL_NAME} chown -R urbackup:urbackup /usr/local/share/urbackup /config
iocage exec ${JAIL_NAME} sysrc urbackup_server_enable="YES"
iocage exec ${JAIL_NAME} service urbackup_server start
iocage exec ${JAIL_NAME} chmod u+x /usr/local/etc/rc.d/urbackup_server
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

#iocage exec ${JAIL_NAME} tar -zcpf /config/server_ident.tar.gz /var/urbackup/server_ident.*

echo "UrBackup should be available at http://${JAIL_IP}:55414"

