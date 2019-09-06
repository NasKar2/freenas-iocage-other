#!/bin/sh
# Build an iocage jail under FreeNAS 11.2 with  lazylibrarian
# https://github.com/NasKar2/freenas-iocage-other
# Thanks to ByteNick for his instructions
# https://www.ixsystems.com/community/threads/lazylibrarian-install-in-11-2-iocage-jail-help.72049/#post-527244

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
LAZYLIB_DATA=""
MEDIA_LOCATION=""
TORRENTS_LOCATION=""


SCRIPT=$(readlink -f "$0")
SCRIPTPATH=$(dirname "$SCRIPT")
. $SCRIPTPATH/lazylib-config
CONFIGS_PATH=$SCRIPTPATH/configs
RELEASE=$(freebsd-version | sed "s/STABLE/RELEASE/g")

# Check for lazylib-config and set configuration
if ! [ -e $SCRIPTPATH/lazylib-config ]; then
  echo "$SCRIPTPATH/lazylib-config must exist."
  exit 1
fi

# Check that necessary variables were set by lazylib-config
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

if [ -z $LAZYLIB_DATA ]; then
  echo 'Configuration error: LAZYLIB_DATA must be set'
  exit 1
fi

if [ -z $MEDIA_LOCATION ]; then
  echo 'Configuration error: MEDIA_LOCATION must be set'
  exit 1
fi

#
# Create Jail

#echo '{"pkgs":["nano","unrar","git","wget","","python","py27-sqlite3"]}' > /tmp/pkg.json
echo '{"pkgs":["git","wget","openssl","readline","pcre","libnghttp2","python36","py36-setuptools","py36-sqlite3","py36-openssl","unrar","ca_root_nss"]}' > /tmp/pkg.json
iocage create --name "${JAIL_NAME}" -p /tmp/pkg.json -r $RELEASE ip4_addr="${INTERFACE}|${JAIL_IP}/24" defaultrouter="${DEFAULT_GW_IP}" boot="on" host_hostname="${JAIL_NAME}" vnet="${VNET}"

rm /tmp/pkg.json

# fix 'libdl.so.1 missing' error in 11.1 versions, by reinstalling packages from older FreeBSD release
# source: https://forums.freenas.org/index.php?threads/openvpn-fails-in-jail-with-libdl-so-1-not-found-error.70391/
if [ "${RELEASE}" = "11.1-RELEASE" ]; then
  iocage exec ${JAIL_NAME} sed -i '' "s/quarterly/release_2/" /etc/pkg/FreeBSD.conf
  iocage exec ${JAIL_NAME} pkg update -f
  iocage exec ${JAIL_NAME} pkg upgrade -yf
fi

# Create directories in FN
mkdir -p ${POOL_PATH}/media/audiobooks
mkdir -p ${POOL_PATH}/media/comics
mkdir -p ${POOL_PATH}/media/magazines
mkdir -p ${POOL_PATH}/media/books
mkdir -p ${POOL_PATH}/media/downloads/sabnzbd/complete/books
#
# Create directories in jail
iocage exec ${JAIL_NAME} "mkdir -p /usr/local/etc/pkg/repos"
iocage exec ${JAIL_NAME} "mkdir -p /config"
iocage exec ${JAIL_NAME} "mkdir -p /mnt/configs"
iocage exec ${JAIL_NAME} "mkdir -p /mnt/torrents"
iocage exec ${JAIL_NAME} "mkdir -p /mnt/nzb"
iocage exec ${JAIL_NAME} "mkdir -p /mnt/media/audiobooks"
iocage exec ${JAIL_NAME} "mkdir -p /mnt/media/books"
iocage exec ${JAIL_NAME} "mkdir -p /mnt/media/comics"
iocage exec ${JAIL_NAME} "mkdir -p /mnt/media/magazines"

# create the apps dirs:
mkdir -p ${POOL_PATH}/${APPS_PATH}/${JAIL_NAME}
iocage exec ${JAIL_NAME} "mkdir -p /usr/local/etc/pkg/repos"
iocage fstab -a ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/${APPS_PATH}/_common_/repos /usr/local/etc/pkg/repos nullfs ro 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/${APPS_PATH}/${JAIL_NAME} /config nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/torrents /mnt/torrents nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/nzb /mnt/nzb nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/media/audiobooks /mnt/media/audiobooks nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/media/books /mnt/media/books nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/media/comics /mnt/media/comics nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/media/magazines /mnt/media/magazines nullfs rw 0 0
iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/media /mnt/media nullfs rw 0 0

# the above structure is similar to what I use, but it can obviously adapted

# getting Lazylibrarian:
iocage exec ${JAIL_NAME} "ln -s /usr/local/bin/python3.6 /usr/local/bin/python"
iocage exec ${JAIL_NAME} git clone https://gitlab.com/LazyLibrarian/LazyLibrarian.git /usr/local/share/lazylibrarian

# this is requested (don't know why), and cannot install it from FN:
#iocage exec ${JAIL_NAME} "export PATH=$PATH:/urllib3"
iocage exec ${JAIL_NAME} "git clone git://github.com/urllib3/urllib3.git /urllib3"
#iocage exec ${JAIL_NAME} "cd /urllib3"
#echo "cd /urllib3"
#iocage exec ${JAIL_NAME} "python /urllib3/setup.py install"
#echo "rm -rf /urllib3"
#iocage exec ${JAIL_NAME} "rm -rf /urllib3"

# defining the rights and prepare the setup:
iocage exec ${JAIL_NAME} "pw user add lazylibrarian -c lazylibrarian -u 111 -d /nonexistent -s /usr/bin/nologin"
iocage exec ${JAIL_NAME} chown -R lazylibrarian:lazylibrarian /usr/local/share/lazylibrarian /config


#
# needed for installing from ports
#mkdir -p ${PORTS_PATH}/ports
#mkdir -p ${PORTS_PATH}/db

#mkdir -p ${POOL_PATH}/${APPS_PATH}/${LAZYLIB_DATA}
#mkdir -p ${POOL_PATH}/${MEDIA_LOCATION}/books
#mkdir -p ${POOL_PATH}/${MEDIA_LOCATION}/downloads/sabnzbd/complete/books
#echo "mkdir -p '${POOL_PATH}/${APPS_PATH}/${LAZYLIB_DATA}'"

lazylib_config=${POOL_PATH}/${APPS_PATH}/${LAZYLIB_DATA}
iocage exec ${JAIL_NAME} 'sysrc ifconfig_epair0_name="epair0b"'

#
# mount ports so they can be accessed in the jail
#iocage fstab -a ${JAIL_NAME} ${PORTS_PATH}/ports /usr/ports nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${PORTS_PATH}/db /var/db/portsnap nullfs rw 0 0

#iocage fstab -a ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${lazylib_config} /config nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/${MEDIA_LOCATION}/books /mnt/books nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/${TORRENTS_LOCATION} /mnt/torrents nullfs rw 0 0
#iocage fstab -a ${JAIL_NAME} ${POOL_PATH}/${MEDIA_LOCATION}/downloads/sabnzbd/complete/books /mnt/sabnzbd/books nullfs rw 0 0
##iocage exec ${JAIL_NAME} -- mkdir /usr/local/share/
#iocage exec ${JAIL_NAME} git clone https://gitlab.com/LazyLibrarian/LazyLibrarian.git /usr/local/share/lazylibrarian
#iocage exec ${JAIL_NAME} python /usr/local/share/lazylibrarian/LazyLibrarian.py -d
#exit
iocage exec ${JAIL_NAME} "pw user add media -c media -u 8675309  -d /nonexistent -s /usr/bin/nologin"
iocage exec ${JAIL_NAME} "pw groupadd -n media -g 8675309"
iocage exec ${JAIL_NAME} "pw groupmod media -m lazylibrarian"
iocage exec ${JAIL_NAME} chown -R media:media /usr/local/share/lazylibrarian /config

echo "make rc.d dir for lazylib"
#iocage exec ${JAIL_NAME} " mkdir /usr/local/etc/rc.d"
iocage exec ${JAIL_NAME} cp -f /mnt/configs/lazylibrarian /usr/local/etc/rc.d/lazylibrarian
iocage exec ${JAIL_NAME} chmod u+x /usr/local/etc/rc.d/lazylibrarian
iocage exec ${JAIL_NAME} chown media:media /usr/local/etc/rc.d/lazylibrarian
iocage exec ${JAIL_NAME} sysrc lazylibrarian_enable="YES"
iocage exec ${JAIL_NAME} sysrc lazylibrarian_user="media"
iocage exec ${JAIL_NAME} sysrc lazylibrarian_dir="/usr/local/share/lazylibrarian"
iocage exec ${JAIL_NAME} service lazylibrarian start

#
# Make pkg upgrade get the latest repo
iocage exec ${JAIL_NAME} mkdir -p /usr/local/etc/pkg/repos/
iocage exec ${JAIL_NAME} cp -f /mnt/configs/FreeBSD.conf /usr/local/etc/pkg/repos/FreeBSD.conf

#
# Upgrade to the lastest repo
#iocage exec ${JAIL_NAME} pkg upgrade -y
#iocage restart ${JAIL_NAME}

#
# remove /mnt/configs as no longer needed
#iocage fstab -r ${JAIL_NAME} ${CONFIGS_PATH} /mnt/configs nullfs rw 0 0

#
# Make media owner of data directories
chown -R media:media ${POOL_PATH}/${MEDIA_LOCATION}
chown -R media:media ${POOL_PATH}/${TORRENTS_LOCATION}
#iocage exec ${JAIL_NAME} python /usr/local/share/lazylibrarian/LazyLibrarian.py -d
iocage exec ${JAIL_NAME} "service lazylibrarian start"
echo
RED='\033[0;31m'
NC='\033[0m' # No Color
printf "${RED}****************************************************${NC}\n"
echo "go into jail and execute these commands"
echo "iocage console ${JAIL_NAME}"
echo "cd /urllib3"
echo "python setup.py install"
echo "exit" 
printf "${RED}****************************************************${NC}\n"
echo
echo "LAZYLIBRARIAN should be available at http://${JAIL_IP}:5299"

