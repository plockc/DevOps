#!/bin/bash

set -e

function usage() {
cat <<EOF
$(basename "$0"): will set up ssh keys for remote host
Usage: $(basename "$0") [switches] [--] \[user\@\]remoteHost
      -h              This help
      -p descriptor   The numerical id (like 1 for stdin) to read the password
                      This is used by sshpass to help set up ssh connection to avoid terminal input
                      Examples: echo "password" | $0 -p0 remoteUser@remoteHost
                                $0 -p3 remoteUser@remoteHost 3<<<"password"
EOF
}

# leading ':' to run silent, 'f:' means f need an argument, 'h' is just an option
while getopts ":f:hp:" opt; do case $opt in
	h)  usage; exit 0;;
	p)  PASS=$(cat /dev/fd/${OPTARG});;
	\?) usage; echo "Invalid option: -$OPTARG" >&2; exit 1;;
        # this happens when silent and missing argument for option
	:)  usage; echo "-$OPTARG requires an argument" >&2; exit 1;;
	*)  usage; echo "Unimplemented option: -$OPTARG" >&2; exit 1;; # catch-all
esac; done

shift $((OPTIND-1))

if (( $# != 1 )); then echo "missing remoteHost"; echo; usage; exit 1; fi

# GET THE REMOTE HOST
remoteHost=${1#*@} # sucks away all the leading characters until @

set +e
hostCheck=$(host ${remoteHost})
set -e

# CHECK FOR REMOTE HOST EXISTENCE
if [[ ! "${hostCheck}" =~ "has address" ]]; then
	echo Cannot resolve host ${remoteHost}
	exit 1
fi

hostIp=$(echo "${hostCheck}" | awk '{print $4}')

# GET REMOTE USER
remoteUser=${1/${remoteHost}/} # sucks away all the trailing characters after and including '@'
remoteUser=${remoteUser%?} # removes trailing @
remoteUser=${remoteUser:=$USER}

function deleteKey {
	echo && read -p "Delete old key? [Yn] "
	if [[ ! $REPLY =~ ^[Nn]$ ]]; then
		echo removing old keys for $1
		ssh-keygen -R $1
	fi
}

function testConnection {
	echo && echo Testing connection to ${remoteUser}@${remoteHost} / ${hostIp}

	set +e
	sshConnection=$(ssh -l $remoteUser -oBatchMode=yes -oConnectTimeout=2 ${remoteHost} echo connected 2>&1 \
	  | tr -d '\r\n' | sed -e 's/.*been changed.*/Host key changed/')
	# Operation timed out, Host key verification failed, Host key changed, Connection refused, Could not resolve hostname, Permission denied, Missing Host Key
	set -e

	# test for hostname move or ip move based on command output
	# should test first for host key changed, then remove entries
	# 
	# to try without password (key only)
	# -oPasswordAuthentication=no 

	if [[ $sshConnection == "connected" ]]; then
		echo && echo Connection verified
	elif [[ $sshConnection =~ "Permission denied" ]]; then
		if ! which -s ssh-copy-id; then
			# suggest installing homebrew
			if ! which -s brew; then
			  echo "on mac, homebrew can install ssh-copy-id, to install homebrew:"
			  echo && echo ruby -e \"\$\(curl -fsSL https://raw.github.com/mxcl/homebrew/go\)\";
			  echo && echo then install ssh-copy-id like:
			  echo && echo brew install ssh-copy-id
			fi
			echo either install ssh keys yourself or install ssh-copy-id and rerun this script, it will copy ssh keys to ${remoteHost} for you
            exit 1;
		fi
		# set up ssh keys for root account
		if [[ ! -e ~/.ssh/id_dsa ]]; then
		  echo Creating dsa key for ssh and adding to ssh-agent, come back later and encrypt your provate key with a passphrase
		  mkdir -m 700 -p ~/.ssh
		  ssh-keygen -q -N '' -t dsa -f ~/.ssh/id_dsa;
		  ssh-add
		fi
		# copy key to the destination server
		echo copying key to $remoteHost
		if [[ -z "${PASS}" ]]; then
            ssh-copy-id -i ~/.ssh/id_dsa.pub ${remoteUser}@${remoteHost} > /dev/null;
		else
    		# add all keys registered with ssh-agent to remote authorized keys using sshpass to allow password auth
	        ssh-add -L | sshpass -d3 ssh ${remoteUser}@${remoteHost} "test -d ~/.ssh || mkdir --mode=700 .ssh; cat >> ~/.ssh/authorized_keys" 3<<<"$PASS"
	    fi
        echo && echo "Trying again"
		testConnection
	elif [[ $sshConnection =~ "Host key verification failed" || $sshConnection =~ "Host key changed" ]]; then
		echo && echo "Remote Fingerprint"
		ssh-keyscan ${remoteHost} 2>/dev/null | ssh-keygen -lv -F ${remoteHost} -f /dev/stdin
		if grep -q ${remoteHost} ~/.ssh/known_hosts; then
			echo && echo "Host key has changed, deleting entry for Host ${remoteHost}:"
			ssh-keygen -lv -F ${remoteHost} -f ~/.ssh/known_hosts
			deleteKey ${remoteHost}
		fi
		if grep -q ${hostIp} ~/.ssh/known_hosts; then
			echo && echo "Deleting entry for IP ${hostIp}:"
			ssh-keygen -lv -F ${hostIp} -f ~/.ssh/known_hosts
			deleteKey ${hostIp}
		fi
		echo && read -p "Add new host key? [Yn] "
		if [[ ! $REPLY =~ ^[Nn]$ ]]; then
			ssh-keyscan ${remoteHost} 2>/dev/null >> ~/.ssh/known_hosts
			ssh-keyscan ${hostIp} 2>/dev/null >> ~/.ssh/known_hosts
			echo && echo "Trying again"
			testConnection
		fi
	else
		echo && echo "Failed connection to ${remoteUser}@${remoteHost} because: ${sshConnection}"
		exit 1;
	fi
}

testConnection
