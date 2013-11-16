#!/bin/bash

# must be run as root
# can set BACKUP_ROOT_DIR for the root of the backups
#    backups will be full paths under BACKUP_ROOT_DIR/

# can debug the launchdaemon with "sudo launchctl log level debug, tail -f /var/log/system.log"
# 
# return logging back to normal with 
# sudo launchctl log level error

# temporarily you can add to the plist dictionary:
#      <key>StandardOutPath</key><string>/var/log/progname.log</string>
#      <key>StandardErrorPath</key><string>/var/log/progname_err.log</string>

# you can see your jobs with "launchctl list | grep backup"

# rerunning this file will unload the daemon and load it back for you

# to manually remove the job, you need to unload it from launchctl, mark it as disabled, and delete the file
# find the file in /Libary/LaunchDaemons (for root) or ~/Library/LaunchAgents (for users)
# launchctl unload -w <path>/${reverseHost}.backup.${remoteUser}.${label}.${interval}.plist
# rm <path>/${reverseHost}.backup.${remoteUser}.${label}.${interval}.plist

# some good plist info: http://www.mactech.com/articles/mactech/Vol.25/25.09/2509MacEnterprise-launchdforLunch/index.html

set -e

function usage {
	echo "$0" \<simple-label\> \<backupTemplateFile\> \[user\@\]remoteHost emailRecipient
}

if (( $# == 0 )); then usage; exit 1; fi

label=$1
emailRecipient="$4"
emailRecipient=${emailRecipient:=$USER}

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
(( `id -u` == 0 )) && defaultBackupRootDir='/var/root/rsnapshots' || defaultBackupRootDir=~/Documents/RemoteBackups
backupRootDir=${BACKUP_ROOT_DIR:=${defaultBackupRootDir}}

# GET BACKUP DIR FOR THIS BACKUP
backupDestinationDir=${backupRootDir}/${remoteHost}-${remoteUser}-${label}
if [[ -e "${backupDestinationDir}" && ! $(find ${backupDestinationDir} -maxdepth 0 -empty) ]]; then
	printf "\nYou must chose a non-existant or empty directory\n"
	exit 1
elif [[ ! -e "${backupDestinationDir}" ]]; then
	echo && echo Creating dir ${backupDestinationDir}
	mkdir -p ${backupDestinationDir} || echo why weird exit status for mkdir -p
fi
chmod 700 ${backupDestinationDir} || echo weird chmod exit status

# CREATE RSNAPSHOT CONFIGURATION
if (( `id -u` != 0 )); then
	rsnapshotConfigBase=~/.rsnapshot
	lockfile=~"/.rsnapshot/rsnapshot-${remoteHost}-${remoteUser}-${label}.pid"
else
	rsnapshotConfigBase='/var/root/.rsnapshot'
	lockfile="/var/run/rsnapshot-${remoteHost}-${remoteUser}-${label}.pid"
fi
rsnapshotConfigParentDir="${rsnapshotConfigBase}/${remoteHost}"
rsnapshotConfig="${rsnapshotConfigParentDir}/${remoteUser}-${label}.config"

echo && echo rsnapshot configuration is at ${rsnapshotConfig}

# create backup script and stick it into the root's bin directory if not already there
if [[ ! -f "${rsnapshotConfig}" ]]; then
	mkdir -p "${rsnapshotConfigParentDir}"
	cat <(remoteHost=$remoteHost remoteUser=$remoteUser reverseHost=$reverseHost \
		  label=$label backupDestinationDir=$backupDestinationDir lockfile=${lockfile} \
		  bash <<OUTER
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
	# note first tab is ignored with <<- allowing us to pretty print
	cat >${plistFile} <<-EOF
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
	<plist version="1.0">
	<dict>
	  <key>Label</key><string>${reverseHost}.backup.${remoteUser}.${label}.${interval}</string>
	  <key>LowPriorityIO</key><true/>
	  <key>ProgramArguments</key>
	  <array>
	    <string>/bin/bash</string>
	    <string>-c</string>
	    <string>`which rsnapshot` -c ${rsnapshotConfig} ${interval}  2&gt;&amp;1 | /usr/bin/mail -E -s ${reverseHost}.backup.${remoteUser}.${label}.${interval} ${emailRecipient}</string>
	  </array>
	  <key>StartCalendarInterval</key>
	  <array>
	    <dict>
	      ${schedule}
	    </dict>
	  </array>
	  <!-- this lets the spawn mail send complete - http://unflyingobject.com/blog/posts/996 -->
	  <key>AbandonProcessGroup</key><true/>
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

echo && echo done setting up backups for $label
