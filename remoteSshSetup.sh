set -e

function usage {
	echo ./remoteSshSetup \[user\@\]remoteHost 
}

if (( $# != 1 )); then usage; exit 1; fi

# GET THE REMOTE HOST
remoteHost=${1#*@} # sucks away all the leading characters until @

hostCheck=$(host ${remoteHost})
# CHECK FOR REMOTE HOST EXISTANCE
if [[ ! "${hostCheck}" =~ "has address" ]]; then
	echo Cannot resolve host ${remoteHost}
	exit 1
fi

hostIp=$(echo "${hostCheck}" | awk '{print $4}')

# GET REMOTE USER
remoteUser=${1/${remoteHost}/} # sucks away all the trailing characters after and including '@'
remoteUser=${remoteUser%?} # removes trailing @
remoteUser=${remoteUser:=$USER}

echo && echo Verifying connection to ${remoteUser}@${remoteHost} / ${hostIp}
set +e
sshConnection=$(ssh -l $remoteUser -oBatchMode=yes -oConnectTimeout=2 ${remoteHost} echo connected 2>&1 \
  | tr -d '\r\n' | sed -e 's/.*been changed.*/Host key changed/')
# Operation timed out, Host key verification failed, Host key changed, Connection refused, Could not resolve hostname, Permission denied, Missing Host Key

set -e


function deleteKey {
	echo && read -p "Delete old key? [Yn] "
	if [[ ! $REPLY =~ ^[Nn]$ ]]; then
		echo removing old keys for $1
		ssh-keygen -R $1 -f ${sshDir}/known_hosts
	fi
}

# test for hostname move or ip move outputs
# should test first for host key changed, then remove entries
# 
# to try without password (key only)
# -oPasswordAuthentication=no 

(( `id -u` == 0 )) && sshDir='/var/root/.ssh' || sshDir=~/.ssh

if [[ $sshConnection == "connected" ]]; then
	echo && echo Connection verified
elif [[ $sshConnection =~ "Permission denied" ]]; then
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
	if ssh-copy-id -i ${sshDir}/id_dsa.pub ${remoteUser}@${remoteHost} > /dev/null; then
	  echo && echo "Trying again"
	  $0 $@
	fi
elif [[ $sshConnection =~ "Host key verification failed" ]]; then
	echo && echo "Remote Fingerprint"
	ssh-keyscan ${remoteHost} 2>/dev/null | ssh-keygen -lv -F ${remoteHost} -f /dev/stdin
	if grep -q ${remoteHost} ${sshDir}/known_hosts; then
		echo && echo "Host key has changed, Current entry for Host:"
		ssh-keygen -lv -F ${remoteHost} -f ${sshDir}/known_hosts
		deleteKey ${remoteHost}
	fi
	if grep -q ${hostIp} ${sshDir}/known_hosts; then
		echo && echo "Current entry for IP:"
		ssh-keygen -lv -F ${hostIp} -f ${sshDir}/known_hosts
		deleteKey ${hostIp}
	fi
	echo && read -p "Add key? [Yn] "
	if [[ ! $REPLY =~ ^[Nn]$ ]]; then
		ssh-keyscan alarmpi 2>/dev/null >> ${sshDir}/known_hosts
		echo && echo "Trying again"
		$0 $@
	fi
else
    echo && echo "Failed connection to ${remoteUser}@${remoteHost} because: ${sshConnection}"
    exit 1;
fi
