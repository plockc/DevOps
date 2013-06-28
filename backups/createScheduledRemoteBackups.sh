#!/bin/bash

# must be run as root
# must pass in a plist template file path as first argument
# can set BACKUP_ROOT_DIR for the root of the backups
#    backups will be full paths under BACKUP_ROOT_DIR/

# can debug the launchdaemon with
# sudo launchctl log level debug
# tail -f /var/log/system.log
# and you might need <key>StandardOutPath</key><string>/var/log/progname.log</string>
#                    <key>StandardErrorPath</key><string>/var/log/progname_err.log</string>

# some good plist info: http://www.mactech.com/articles/mactech/Vol.25/25.09/2509MacEnterprise-launchdforLunch/index.html

set -e

function usage {
	echo ./setupBakup \<label\> \<backupTemplateFile\> \[user\@\]remoteHost 
}

if (( $# == 0 )); then usage; exit 1; fi

label=$1 # if label is empty, then set to 'default'

# GET THE REMOTE HOST
remoteHost=${3#*@} # sucks away all the leading characters until @

# CHECK FOR REMOTE HOST EXISTANCE
if [[ ! `host ${remoteHost}` =~ "has address" ]]; then
	echo Cannot resolve host ${remoteHost}
	exit 1
fi

# GET REVERSE HOST FROM REMOTE HOST
for part in ${remoteHost//./ }; do reverseHost=${part}.${reverseHost}; done;
reverseHost=${reverseHost%?} # the % removes the '.' ('?' matches single character) from the end

# GET REMOTE USER
remoteUser=${3/${remoteHost}/} # sucks away all the trailing characters after and including '@'
remoteUser=${remoteUser%?} # removes trailing @
remoteUser=${remoteUser:=$USER}

# GET ROOT FOR BACKUPS
(( `id -u` == 0 )) && defaultBackupRootDir='/var/root/rsnapshots' || defaultBackupRootDir=~/Documents/Backups
backupRootDir=${BACKUP_ROOT_DIR:=${defaultBackupRootDir}}

# GET BACKUP DIR FOR THIS BACKUP
backupDestinationDir=${backupRootDir}/${remoteHost}/${remoteUser}-${label}
if [[ -e "${backupDestinationDir}" && ! $(find ${backupDestinationDir} -maxdepth 0 -empty) ]]; then
	echo && echo You must chose a non-existant or empty directory
	exit 1
elif [[ ! -e "${backupDestinationDir}" ]]; then
	echo && echo Creating dir ${backupDestinationDir}
	mkdir -p ${backupDestinationDir} || echo why weird exit status for mkdir -p
fi
chmod 700 ${backupDestinationDir} || echo weird chmod exit status

echo && echo Verifying connection to ${remoteUser}@${remoteHost}
set +e
sshConnection=$(ssh -l $remoteUser -oBatchMode=yes -oConnectTimeout=2 ${remoteHost} echo connected 2>&1 \
  | tr -d '\r\n' | sed 's/.*been changed.*/Host key changed/')
# Operation timed out, Host key verification failed, Host key changed, Connection refused, Could not resolve hostname, Permission denied
set -e

# test for hostname move or ip move outputs
# should test first for host key changed, then remove entries
# 
# to try without password (key only)
# -oPasswordAuthentication=no 

(( `id -u` == 0 )) && sshDir='/var/root/.ssh' || sshDir=~/.ssh

if [[ $sshConnection == "connected" ]]; then
	echo && echo Connection verified
elif [[ $sshConnection =~ "Permission denied" ]]; then
    echo Failed connection to ${remoteUser}${remoteHost} because: ${sshConnection}
    if ! which -s ssh-copy-id; then
		# suggest installing homebrew
		if ! which -s brew; then
		  echo "Install homebrew or ssh-copy-id so we can install ssh keys, to install homebrew:"
		  echo ruby -e \"\$\(curl -fsSL https://raw.github.com/mxcl/homebrew/go\)\";
		  exit 1;
		else
		  echo brew installing ssh-copy-id
		  brew install ssh-copy-id;
		fi
	fi
	# set up ssh keys for root account
	if [[ ! -e ${sshDir}/id_dsa ]]; then
	  echo Creating dsa key for ssh
	  mkdir -p ${sshDir}
	  ssh-keygen -q -N '' -t dsa -f ${sshDir}/id_dsa;
	fi
	# copy key to the destination server
	echo copying key to $remoteHost
	ssh-copy-id -i ${sshDir}/id_dsa.pub ${remoteUser}@${remoteHost}
else
    echo && echo Failed connection to ${remoteUser}@${remoteHost} because: ${sshConnection}
    exit 1;
fi

# CREATE RSNAPSHOT CONFIGURATION
(( `id -u` == 0 )) && rsnapshotConfigBase='/var/root/.rsnapshot' || rsnapshotConfigBase=~/.rsnapshot
rsnapshotConfigParentDir="${rsnapshotConfigBase}/${remoteHost}"
rsnapshotConfig="${rsnapshotConfigParentDir}/${remoteUser}-${label}.config"

echo && echo rsnapshot configuration is at ${rsnapshotConfig}

# create backup script and stick it into the root's bin directory if not already there
if [[ ! -f "${rsnapshotConfig}" ]]; then
	mkdir -p "${rsnapshotConfigParentDir}"
	cat <(remoteHost=$remoteHost remoteUser=$remoteUser reverseHost=$reverseHost \
		  label=$label backupDestinationDir=$backupDestinationDir bash <<OUTER
cat <<INNER
`cat $2`
INNER
OUTER
) > "${rsnapshotConfig}"
	echo && echo Created rsnapshot configuration at ${rsnapshotConfig}
fi

(( `id -u` == 0 )) && launchctlDir='/Library/LaunchDaemons' || launchctlDir=~/Library/LaunchAgents

function createPlist {
local interval=$1
local schedule=$2
plistFile="${launchctlDir}/${reverseHost}.backup.${remoteUser}.${label}.${interval}.plist"
# if it is already there unload it first so we can load the new one
if [[ -e ${plistFile} ]]; then
	echo unloading old ${plistFile}
	launchctl unload ${plistFile}
fi
# this treat the path passed into the script as a template with bash variable expansion
# we have to update the runtime environment of bash as the locals are not copied
# note frist tab is ignored with <<- allowing us to pretty print
cat >${plistFile} <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${reverseHost}.backup.${remoteUser}.${label}.${interval}</string>
	<key>LowPriorityIO</key><true/>
    <key>ProgramArguments</key>
    <array>
		<string>`which rsnapshot`</string>
		<string>-c</string>
		<string>${rsnapshotConfig}</string>
		<string>${interval}</string>
    </array>
    <key>StartCalendarInterval</key>
    <array>
		<dict>
		  ${schedule}
		</dict>
    </array>
</dict>
</plist>
EOF
chmod 644 ${plistFile}
launchctl load ${plistFile}
echo && echo created and launched ${plistFile}
}

function keyVal { echo "<key>${1}</key><integer>${2}</integer>"; }

createPlist hourly "$(keyVal Minute 0)"
createPlist daily  "$(keyVal Hour 1)$(keyVal Minute 10)"
createPlist weekly "$(keyVal Weekday 0)$(keyVal Hour 2)$(keyVal Minute 25)"
createPlist monthly "$(keyVal Day 1)$(keyVal Hour 3)$(keyVal Minute 40)"
