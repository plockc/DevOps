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
$(basename "$0"): will install and configure arch linux on a raspberry pi
Usage: $(basename "$0") [switches] [--]
      -f archImage    Location of the arch linux image .iso
      -u user         Local user that needs to be set up for ssh
                      Defaults to the user that is running this as sudo (or root if root)
      -h              This help
      -p descriptor   The numerical id (like 1 for stdin) to read the password
                      This is used by sshpass to help set up ssh connectivity to avoid terminal input
                      Examples: echo "password" | $0 -p0 remoteUser@remoteHost
                               $0 -p3 remoteUser@remoteHost 3<<<"password"
Hint: if you see end of file without any output, make sure you can ssh without problems
EOF
}

# setup ssh user default, can be overridden below
if [[ -n "${SSH_USER}" ]]; then ssh_user="${SSH_USER}"; else ssh_user="${USER}"; fi

# leading ':' to run silent, 'f:' means f need an argument, 'c' is just an option
while getopts ":f:hu:p:" opt; do case $opt in
	h)  usage; exit 0;;
	p)  PASS="${OPTARG}"; useSshPass="-p 0";;
	u)  ssh_user="${OPTARG}";;
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

echo "=================================================================================="
echo "Just remove the SD card (it is already ejected) and install it to the Raspberry Pi then power on the Pi, then hit enter here to continue.  When prompted, use \"root\" as the default password"

read -p "Hit Enter to continue: "
sleep 28

# flush dns cache
killall -HUP mDNSResponder

# #############
#  NEED TO FIGURE OUT WHICH USER TO RUN AS
# #############

su -l ${ssh_user} bash <(curl -fsSL https://raw.github.com/plockc/DevOps/master/remoteSshSetup.sh) ${useSshPass} root@alarmpi <<< "${PASS}"

echo "=================================================================================="
echo "Pi OS installed, now configuring and updating packages
echo "=================================================================================="

# POST INSTALLATION
set +e
# base64 the post install file locally then the remote bash will see a file of the base64 decoded contents
ssh -t root@alarmpi bash \<\(base64 --decode --ignore-garbage \<\<\< $(curl -fsSL https://raw.github.com/plockc/ArchDevOps/master/archInstall/archPiPostInstall.sh | base64)\) 
set -e

sleep 25

# really need to know the new host here, at which point we could tweak out the hostname for the key

