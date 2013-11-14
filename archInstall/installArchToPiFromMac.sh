#!/bin/bash

# stop on any errors
set -e

function usage() {
cat <<EOF
$(basename "$0"): will install and configure arch linux on a raspberry pi
    requires root priviliges
Usage: $(basename "$0") [switches] [--]
      -f archImage     Location of the arch linux image .iso
      -u user          Local user that needs to be set up for ssh
                       Defaults to the user that is running this as sudo (or root if root)
      -n host.domain   New hostname and domain for the pi
      -h               This help
      -p descriptor    The numerical id (like 1 for stdin) to read the new root password
                       This is used by sshpass to help set up ssh connectivity to avoid
                       terminal input
                       Examples: $0 -p3 ... 3<<<"password"
                                 $0 -p3 ... 3<<<"\$(read -p 'new pass: ' && echo $REPLY)"
                                 Note: with sudo you need to provide file descriptors to
                                       the command, not to sudo
                                       sudo bash -c '$0 -p3 ... 3<<<"password"'

EOF
}

# ensure root
if (( `id -u` != 0 )); then
  echo Please run with sudo
  exit 1
fi

# setup ssh user default, can be overridden below
if [[ -n "${SUDO_USER}" ]]; then ssh_user="${SUDO_USER}"; else ssh_user="${USER}"; fi

# leading ':' to run silent, 'f:' means f need an argument, 'h' is just an option
while getopts ":f:hu:n:p:" opt; do case $opt in
	h)  usage; exit 0;;
	    # user passes in the file descriptor for this script to read in the password
	    # then we will use fd3 to pass it into the archiPiPostInstall script
	p)  PASSFLAG="-p 3"; NEWPASSWORD=$(cat /dev/fd/${OPTARG});;
	u)  ssh_user="${OPTARG}";;
	n)  NEWHOSTNAME="${OPTARG}"; NEWHOSTNAME_POST_INSTALL_FLAG="-n ${NEWHOSTNAME}";;
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
echo Waiting for boot process to complete
sleep 40

# flush dns cache
killall -HUP mDNSResponder

hostInfo=$(host alarmpi) || (printf "\nfailed to find pi, try restarting it and completing manually\n"; exit 1)

echo pi comes up as $hostInfo

echo && echo Setting up ssh connectivity for ${ssh_user} to root user on raspberry pi, you may be prompted for ssh key passphrases
# the -l on the bash is needed to get the proper PATH
su -l ${ssh_user} -c 'eval $(ssh-agent) > /dev/null && echo adding keys && (ssh-add || echo no keys found) && echo setting up && bash -l <(curl -fsSL https://raw.github.com/plockc/DevOps/master/remoteSshSetup.sh) -p 3 root@alarmpi 3<<<"root"'

echo "=================================================================================="
echo "Pi OS installed, now configuring and updating packages"
echo "=================================================================================="

# POST INSTALLATION
set +e
# base64 the post install file locally then the remote bash will see a file of the base64 decoded contents
# the NEWSPASSWORD must come last as it includes a file descriptor
# and the fd3 must be quoted so it is executed on the remote box and not locally
su -l ${ssh_user} -c 'ssh -t root@alarmpi bash \<\(base64 --decode --ignore-garbage \<\<\< $(curl -fsSL https://raw.github.com/plockc/ArchDevOps/master/archInstall/archPiPostInstall.sh | base64)\) '"${NEWHOSTNAME_POST_INSTALL_FLAG} ${PASSFLAG} '3<<<\"${NEWPASSWORD}\"'"
set -e

# TODO: set up host keys for new hostname, instead of alarmpi

echo Finished post installation, waiting for the reboot
sleep 40

echo Removing any old keys for ${NEWHOSTNAME} and adding new host key
su -l ${ssh_user} -c "bash -l <(curl -fsSL https://raw.github.com/plockc/DevOps/master/remoteSshSetup.sh) root@${NEWHOSTNAME}"

printf "\nCompleted Arch Install to Pi from your Mac, you can ssh root@${NEWHOSTNAME} as ${ssh_user}\n"
