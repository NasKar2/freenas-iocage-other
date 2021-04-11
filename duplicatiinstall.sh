#!/bin/sh
# Build an iocage jail under FreeNAS 11.3 with Duplicati
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
DUPLICATI_DATA=""
BACKUP_LOCATION=""
USE_BASEJAIL="-b"
DUPLICATI_PW=""

SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
. $SCRIPTPATH/duplicati-config
CONFIGS_PATH=$SCRIPTPATH/configs
DB_ROOT_PASSWORD=$(openssl rand -base64 16)
DB_PASSWORD=$(openssl rand -base64 16)
ADMIN_PASSWORD=$(openssl rand -base64 12)
RELEASE=$(freebsd-version | cut -d - -f -1)"-RELEASE"

# Check for duplicati-config and set configuration
if ! [ -e $SCRIPTPATH/duplicati-config ]; then
  echo "$SCRIPTPATH/duplicati-config must exist."
  exit 1
fi

# Check that necessary variables were set by duplicati-config
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
  JAIL_NAME="duplicati"
  echo "JAIL_NAME defaulting to 'duplicati'"
fi
if [ -z $DUPLICATI_DATA ]; then
  DUPLICATI_DATA="duplicati"
  echo "DUPLICATI_DATA defaulting to 'duplicati'"
fi
if [ -z $MEDIA_LOCATION ]; then
  MEDIA_LOCATION="media"
  echo "MEDIA_LOCATION defaulting to 'media'"
fi
if [ -z $BACKUP_LOCATION ]; then
  BACKUP_LOCATION="backup"
  echo "BACKUP_LOCATION defaulting to 'backup'"
fi
if [ -z $DUPLICATI_PW ]; then
  echo "DUPLICATI_PW must be set in duplicati-config"
  exit 1
fi

#
# Create Jail
echo '{"pkgs":["mono","py37-sqlite3","curl","ca_root_nss"]}' > /tmp/pkg.json
if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" ip4_addr="${INTERFACE}|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}" ${USE_BASEJAIL}
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

#
# needed for installing from ports
#mkdir -p ${PORTS_PATH}/ports
#mkdir -p ${PORTS_PATH}/db

#
# Create directories in FreeNAS if they don't exist
mkdir -p ${POOL_PATH}/${APPS_PATH}/${DUPLICATI_DATA}
if [ ! -d "${POOL_PATH}/${BACKUP_LOCATION}" ]; then
  mkdir ${POOL_PATH}/${BACKUP_LOCATION}
fi
if [ ! -d "${POOL_PATH}/restore" ]; then
  mkdir ${POOL_PATH}/restore
fi
if [ ! -d "${POOL_PATH}/scripts" ]; then
  mkdir ${POOL_PATH}/scripts
fi
if [ ! -d "${POOL_PATH}/nextcloud" ]; then
  mkdir ${POOL_PATH}/nextcloud
fi
if [ ! -d "${POOL_PATH}/apps" ]; then
  mkdir ${POOL_PATH}/apps
fi

echo "mkdir -p '${POOL_PATH}/${APPS_PATH}/${DUPLICATI_DATA}'"

duplicati_config=${POOL_PATH}/${APPS_PATH}/${DUPLICATI_DATA}
iocage exec ${JAIL_NAME} 'sysrc ifconfig_epair0_name="epair0b"'

# create dir in jail for mount points
#iocage exec ${JAIL_NAME} mkdir -p /usr/ports
#iocage exec ${JAIL_NAME} mkdir -p /var/db/portsnap
iocage exec ${JAIL_NAME} mkdir -p /config
iocage exec ${JAIL_NAME} mkdir -p /mnt/backup
iocage exec ${JAIL_NAME} mkdir -p /mnt/configs
iocage exec ${JAIL_NAME} mkdir -p /mnt/encrypt
iocage exec ${JAIL_NAME} mkdir -p /mnt/restore
iocage exec ${JAIL_NAME} mkdir -p /mnt/scripts
iocage exec ${JAIL_NAME} mkdir -p /mnt/nextcloud
iocage exec ${JAIL_NAME} mkdir -p /mnt/apps
iocage exec ${JAIL_NAME} mkdir -p /mnt/NextcloudBackups
iocage exec ${JAIL_NAME} mkdir -p /mnt/media/videos/homevideos

# mount ports so they can be accessed in the jail
#iocage fstab -a ${JAIL_NAME} ${PORTS_PATH}/ports /usr/ports nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${PORTS_PATH}/db /var/db/portsnap nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${duplicati_config} /config nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/${BACKUP_LOCATION} /mnt/backup nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/restore /mnt/restore nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/scripts /mnt/scripts nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/nextcloud /mnt/nextcloud nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/nextcloud/files /mnt/nextcloud/files nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/nextcloud/db /mnt/nextcloud/db nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/apps /mnt/apps nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/NextcloudBackups/ /mnt/NextcloudBackups/ nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/media/videos/homevideos/ /mnt/media/videos/homevideos/ nullfs rw 0 0

iocage exec ${JAIL_NAME} "ln -s /usr/local/bin/mono /usr/bin/mono"

# Download Duplicati
FILE="duplicati-2.0.5.1_beta_2020-01-18.zip"
iocage exec ${JAIL_NAME} fetch -o /usr/local/share https://updates.duplicati.com/beta/${FILE}
iocage exec ${JAIL_NAME} -- mkdir -p /usr/local/share/duplicati
iocage exec ${JAIL_NAME} "unzip /usr/local/share/${FILE} -d /usr/local/share/duplicati"
#iocage exec ${JAIL_NAME} "tar -xjf /usr/local/share/"${FILE}" -C /usr/local/share/duplicati"
#iocage exec ${JAIL_NAME} 'rm /usr/local/share/"${FILE}"'

#create user and group
#iocage exec ${JAIL_NAME} "pw user add duplicati -c duplicati -u 818 -d /nonexistent -s /usr/bin/nologin"
#iocage exec ${JAIL_NAME} "pw usermod www -G duplicati"
iocage exec ${JAIL_NAME} "pw user add mysql -c mysql -u 88 -d /nonexistent -s /usr/bin/nologin"
iocage exec ${JAIL_NAME} "pw user add media -c media -u 8675309  -d /nonexistent -s /usr/bin/nologin"
iocage exec ${JAIL_NAME} "pw groupmod wheel -m media"


iocage exec ${JAIL_NAME} chown -R media:media /usr/local/share/duplicati /config /mnt/restore /mnt/encrypt
iocage exec ${JAIL_NAME} mkdir -p /usr/local/etc/rc.d
iocage exec ${JAIL_NAME} cp -f /mnt/configs/duplicati /usr/local/etc/rc.d/
iocage exec ${JAIL_NAME} chmod u+x /usr/local/etc/rc.d/duplicati
iocage exec ${JAIL_NAME} sed -i '' "s/yourpassword/${DUPLICATI_PW}/" /usr/local/etc/rc.d/duplicati
iocage exec ${JAIL_NAME} sed -i '' 's/"duplicati"/"media"/' /usr/local/etc/rc.d/duplicati
iocage exec ${JAIL_NAME} sysrc duplicati_enable="YES"
iocage exec ${JAIL_NAME} sysrc duplicati_user="media"
iocage exec ${JAIL_NAME} sysrc duplicati_group="media"
iocage exec ${JAIL_NAME} sysrc duplicati_dat_dir="/config"
iocage exec ${JAIL_NAME} service duplicati restart

#
# Make pkg upgrade get the latest repo
iocage exec ${JAIL_NAME} mkdir -p /usr/local/etc/pkg/repos/
iocage exec ${JAIL_NAME} cp -f /mnt/configs/FreeBSD.conf /usr/local/etc/pkg/repos/FreeBSD.conf

#
# Upgrade to the lastest repo
iocage exec ${JAIL_NAME} pkg upgrade -y
iocage stop --force ${JAIL_NAME}
iocage start ${JAIL_NAME}

#
# remove /mnt/configs as no longer needed
iocage fstab -r ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0

echo "DUPLICATI installed"
echo "Duplicati can be found at http://${JAIL_IP}:8200"

exit
