#!/bin/sh
# Build an iocage jail under FreeNAS 11.2 with  handbrake
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
HANDBRAKE_DATA=""


SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
. $SCRIPTPATH/handbrake-config
CONFIGS_PATH=$SCRIPTPATH/configs
DB_ROOT_PASSWORD=$(openssl rand -base64 16)
DB_PASSWORD=$(openssl rand -base64 16)
ADMIN_PASSWORD=$(openssl rand -base64 12)
RELEASE=$(freebsd-version | cut -d - -f -1)"-RELEASE"

# Check for handbrake-config and set configuration
if ! [ -e $SCRIPTPATH/handbrake-config ]; then
  echo "$SCRIPTPATH/handbrake-config must exist."
  exit 1
fi

# Check that necessary variables were set by handbrake-config
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

if [ -z $HANDBRAKE_DATA ]; then
  echo 'Configuration error: HANDBRAKE_DATA must be set'
  exit 1
fi

#
# Create Jail

echo '{"pkgs":["nano","autoconf","automake","bash","bzip2","cmake","flac","fontconfig","freetype2","fribidi","git","gcc","lzma","m4","gmake","patch","gtar","harfbuzz","jansson","libass","libiconv","libogg","libsamplerate","libtheora","libtool","libvorbis","libx264","libxml2","nasm","opus","pkgconf","python","speex","yasm"]}' > /tmp/pkg.json
#echo '{"pkgs":["nano","python","ffmpeg","handbrake","libass","lame"]}' > /tmp/pkg.json
if ! iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r "${RELEASE}" ip4_addr="${INTERFACE}|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}"
then
	echo "Failed to create jail"
	exit 1
fi
rm /tmp/pkg.json

iocage exec ${JAIL_NAME} sysrc handbrake_enable="YES"
iocage exec ${JAIL_NAME} service handbrake start

#exit
#
# needed for installing from ports
#mkdir -p ${PORTS_PATH}/ports
#mkdir -p ${PORTS_PATH}/db

mkdir -p ${POOL_PATH}/${APPS_PATH}/${HANDBRAKE_DATA}
echo "mkdir -p '${POOL_PATH}/${APPS_PATH}/${HANDBRAKE_DATA}'"

handbrake_config=${POOL_PATH}/${APPS_PATH}/${HANDBRAKE_DATA}
iocage exec ${JAIL_NAME} 'sysrc ifconfig_epair0_name="epair0b"'

# create dir in jail for mount points
iocage exec ${JAIL_NAME} mkdir -p /usr/ports
iocage exec ${JAIL_NAME} mkdir -p /var/db/portsnap
iocage exec ${JAIL_NAME} mkdir -p /config
iocage exec ${JAIL_NAME} mkdir -p /mnt/media
iocage exec ${JAIL_NAME} mkdir -p /mnt/configs

#
# mount ports so they can be accessed in the jail
#iocage fstab -a ${JAIL_NAME} ${PORTS_PATH}/ports /usr/ports nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${PORTS_PATH}/db /var/db/portsnap nullfs rw 0 0

iocage fstab -a ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${handbrake_config} /config nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/media /mnt/media nullfs rw 0 0

iocage exec ${JAIL_NAME} ln -s /usr/local/bin/mono /usr/bin/mono
iocage exec ${JAIL_NAME} "fetch https://github.com/Jackett/Jackett/releases/download/v0.9.16/Jackett.Binaries.Mono.tar.gz -o /usr/local/share"
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

echo "HANDBRAKE should be available at http://${JAIL_IP}:9117"

