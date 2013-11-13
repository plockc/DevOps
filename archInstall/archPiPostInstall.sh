#!/bin/bash

# EXAMPLE USAGE: (run on the pi)
# bash <(curl -fsSL https://raw.github.com/plockc/ArchDevOps/master/archInstall/archPiPostInstall.sh)

# TODO: option for timezone

set -e

if (( `id -u` != 0 )); then
  echo Please run with sudo
  exit 1
fi

function usage() {
cat <<EOF
$(basename "$0"): expands filesystem, ensures non-default root password, hostname,
                    and adds utilities plus php
Usage: $(basename "$0") [switches] [--]
      -n hostname.domain   New hostname and domain for the pi
      -h                   This help
      -p descriptor        The numerical id (like 1 for stdin) to read the new root password
                           This is used by sshpass to help set up ssh connectivity to avoid terminal input
                           Examples: echo "password" | $0 -p0 remoteUser@remoteHost
                                     read -p "new pass: " && echo $REPLY | $0 -p0 
EOF
}

# leading ':' to run silent, 'f:' means f need an argument, 'h' is just an option
while getopts ":hn:p:" opt; do case $opt in
	h)  usage; exit 0;;
	p)  NEWPASS=$(cat /dev/fd/${OPTARG});;
	n)  NEWHOSTNAME="${OPTARG}";;
	\?) usage; echo "Invalid option: -$OPTARG" >&2; exit 1;;
        # this happens when silent and missing argument for option
	:)  usage; echo "-$OPTARG requires an argument" >&2; exit 1;;
	*)  usage; echo "Unimplemented option: -$OPTARG" >&2; exit 1;; # catch-all
esac; done

pacman --noconfirm -Sy --needed augeas darkstat darkhttpd unzip dnsutils rsync screen git dtach vim
ln --force -s /usr/bin/darkstat /usr/sbin/darkstat

echo && echo Setting new root password
# CHANGE PASSWORD IF STILL THE DEFAULT "ROOT"
salt=`grep root /etc/shadow | sed 's/root:\(\$.*\$.*\)\$.*/\1/'`
defaultPass=`php -r "echo crypt('root', \"${salt//\$/\\\\\\$}\");"`
if grep -q "${defaultPass//\$/\\\$}" /etc/shadow; then
    if [[ -z "${NEWPASS}" ]]; then
        read -s -p "Please enter a new root password: "  # -s for silent
        NEWPASS=$REPLY
        echo
        read -s -p "Please confirm: "
        echo

        if [[ ! "$REPLY" = "$NEW_PASSWORD" ]]; then
            echo Passwords did not match, please try again
            exit
        fi
    fi
    chpasswd << EOSF
root:$NEWPASS
EOSF
fi

echo && echo Setting hostname to $NEWHOSTNAME
# UPDATE HOSTNAME
if grep -q alarmpi <<< `hostname`; then
  if [[ -z "${NEWHOSTNAME}" ]]; then
	  read -p "Please enter the full host name for this Pi: "
	  NEWHOSTNAME=$REPLY
	  if [[ $HOSTNAME == "" ]]
	  then
		echo Please try again with a valid host name
		exit;
	  fi
  fi
  echo $NEWHOSTNAME > /etc/hostname
fi

echo && echo Setting up timezone
# SETUP TIMEZONE
ln --force -s /usr/share/zoneinfo/US/Pacific /etc/localtime

echo && echo Enabling darkstat
# systemctl enable darkstat

echo && echo Resizing filesystem to match the full partition size
# RESIZE THE FILESYSTEM TO MATCH PARTITION SIZE
resize2fs /dev/mmcblk0p2

# let things settle down before going with dhcp else ip will be ignored for some reason
echo "PRE_UP=\"sleep 5\"" >> /etc/network.d/ethernet-eth0

printf "\nRebooting, please wait about 28 seconds before reboot to complete\n"

reboot #would be nice to figure out how to cleanly exit here
