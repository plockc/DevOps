#!/bin/bash

# TODO: remove alarmpi keys from known hosts and ignore unknown host on ssh

# stop on any errors
set -e

# ensure root
if (( `id -u` != 0 )); then
  echo Please run with sudo
  exit 1
fi

function usage() {
cat <<EOF
setupArchOnPi: will install and configure arch linux on a raspberry pi
Usage: $(basename "$0") [switches] [--]
      -f archImage    Location of the arch linux image .iso
      -h                 This help
Hint: if you see end of file without any output, make sure you can ssh without problems
EOF
}

# leading ':' to run silent, 'f:' means f need an argument, 'c' is just an option
while getopts ":f:h" opt; do case $opt in
	h)  usage; exit 0;;
	f)  if [[ ! -e "$OPTARG" ]]; then usage; echo "\$OPTARG" does not exist for -f; exit 1; fi
	    isoFile="$OPTARG";;
	\?) usage; echo "Invalid option: -$OPTARG" >&2; exit 1;;
        # this happens when silent and missing argument for option
	:)  usage; echo "-$OPTARG requires an argument" >&2; exit 1;;
	*)  usage; echo "Unimplemented option: -$OPTARG" >&2; exit 1;; # catch-all
esac; done

if [[ -z "${isoFile}" ]]; then echo "You much specify an iso file with -f"; exit 1; fi

# isoFile gets passed to the script as first argument, script is sourced remotely
bash <(curl -fsSL https://raw.github.com/plockc/DevOps/master/archInstall/imageInstallToSDCard.sh) "$isoFile"

echo "Just remove (it is already ejected) the SD card and install to Raspberry Pi and power the Pi on, then hit enter to continue and use \"root\" for the password when prompted"

read
sleep 25

# flush dns cache
killall -HUP mDNSResponder

# remove previous key since this one was just generated
ssh-keygen -R alarmpi

# add current key
ssh-keyscan alarmpi 2>/dev/null >> ~/.ssh/known_hosts

bash <(curl -fsSL https://raw.github.com/plockc/DevOps/master/remoteSshSetup.sh) root@alarmpi

# POST INSTALLATION
set +e
ssh root@alarmpi base64 --decode --ignore-garbage \<\<\< $(curl -fsSL https://raw.github.com/plockc/ArchDevOps/master/archInstall/archPiPostInstall.sh | base64) \| bash
set -e

sleep 25
