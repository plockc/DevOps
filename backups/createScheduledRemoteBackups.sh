#!/bin/bash

# must be run as root
# must pass in a plist template file path as first argument
# can set BACKUP_ROOT_DIR for the root of the backups
#    backups will be full paths under BACKUP_ROOT_DIR/

# can debug with
# sudo launchctl log level debug
# tail -f /var/log/system.log
# and you might need <key>StandardOutPath</key><string>/var/log/progname.log</string>
#                    <key>StandardErrorPath</key><string>/var/log/progname_err.log</string>

set -e

if (( `id -u` != 0 )); then
	echo Must run this script as root
	exit 1
fi

if (( $# != 1 )) || [[ ! -f $1 ]]; then
	echo Must pass in a plist template file path as first and only argument
	exit 1;
fi

# determine remote host and the reverse (to name the plist)
read -p "hostname for the remote server: " remoteHost
for part in ${remoteHost//./ }; do reverseHost=${part}.${reverseHost}; done;
reverseHost=${reverseHost%?} # the % removes the match of '?' from the end

read -p "Username for the remote server: [$USER] "
remoteUser=${REPLY:=$USER} # if REPLY is empty, then set to current user

echo Verifying connection to ${remoteUser}@${remoteHost}
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

if [[ $sshConnection == "connected" ]]; then
	echo Connection verified
elif [[ $sshConnection =~ "Permission denied" ]]; then
    echo Failed connection to ${remoteHost} because: ${sshConnection}
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
	if ! sudo test -e /var/root/.ssh/id_dsa; then
	  echo Creating dsa key for ssh
	  ssh-keygen -q -N '' -t dsa -f /var/root/.ssh/id_dsa;
	fi
	# copy key to the destination server
	echo copying key to $remoteHost
	ssh-copy-id -i /var/root/.ssh/id_dsa.pub ${remoteUser}@${remoteHost}
else
    echo && echo Failed connection to ${remoteUser}@${remoteHost} because: ${sshConnection}
    exit 1;
fi

# create backup script and stick it into the root's bin directory if not already there
if [[ ! -f /var/root/bin/backupRemoteHost.sh ]]; then
	mkdir -p /var/root/bin
	cat > /var/root/bin/backupRemoteHost.sh <<-EOF
	#!/bin/bash

	# last argument is the local destination, the rest of the arguments are sources
	# expects remoteUser as environment variable

	remoteUser=\${remoteUser:=\$USER} # defaults the remoteUser to current user

	for src in "\${@:1:\$((\$#-1))}"; do  # iterate on arguments ranging from first to next to last
	  echo rsync --relative --archive --quiet --rsh="ssh -l \${remoteUser}" "\${src}" "\${!#}";
	done
	
	# Notes
	# \$(( expr )) does integer math, # is variable for num arguments, the @:x:y is array slicing
	# iterate over the slice of all arguments ( @ ) from the first to the next to last (all the source dirs)
	# ! is a level of indirection (evals the value, which was the number of arguments, then uses that as a var name)
	# so \${!#} becomes the value of the last argument
	EOF
	chmod 755 /var/root/bin/backupRemoteHost.sh
fi

echo && read -p "Provide the local parent directory backup for the backup (no spaces): [$HOME/Documents/Backups/$remoteHost/$label]: "
backupDestinationDir=${BACKUP_ROOT_DIR:="$HOME/Documents/Backups/$remoteHost/$label"}

if [[ -e "${backupDestinationDir}" && ! find ${backupDestinationDir} -maxdepth 0 -empty ]]; then
	echo && echo You must chose a non-existant or empty directory
elif [[ ! find ${backupDestinationDir} -maxdepth 0 -empty ]]; then
	echo && echo Creating dir ${backupDestinationDir}
	mkdir -p ${backupDestinationDir}
fi
chown 

echo && read -p "Provide a label/name for the backup (no spaces): [default]: "
label=${REPLY:="default"} # if label is empty, then set to 'default'

plistFile="/Library/LaunchDaemons/${reverseHost}.backup.${remoteUser}.${label}.plist"

if [[ ! -e "$plistFile" ]] || [[ -e "$plistFile" ]] \
  && read -p "LaunchDaemon already exists, do you want to overwrite? [Ny] " \
  && [[ $REPLY =~ ^[Yy]$ ]]; then
	# this treat the path passed into the script as a template with bash variable expansion
	# we have to update the runtime environment of bash as the locals are not copied
	reverseHost=$reverseHost label=$label remoteUser=$remoteUser remoteHost=$remoteHost \
	# note frist tab is ignored with <<- allowing us to pretty print
	cat <(remoteHost=$remoteHost remoteUser=$remoteUser reverseHost=$reverseHost \
		  label=$label backupDestinationDir=$backupDestinationDir bash <<OUTER
cat <<INNER
`cat $1`
INNER
OUTER
) > ${plistFile}
	chmod 644 ${plistFile}
fi

echo '*************************************************************************'
cat ${plistFile}
echo '*************************************************************************'

# tweak settings in the plist
if read -p "Tweak the rsync settings? [yN] " && [[ $REPLY =~ ^[yY]$ ]]; then
	vi /Library/LaunchDaemons/${reverseHost}.${label}.backup.plist
fi

if echo && read -p "Enable the backups? [yN] " && [[ $REPLY =~ ^[Yy]$ ]]; then
	# enabling the backup
	launchctl load ${plistFile}
fi
