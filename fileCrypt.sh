#!/bin/bash

set -e

function usage() {
cat <<EOF
$(basename "$0"): will either encrypt or decrypt a file using a user supplied password

The password should come first and terminated with a carriage return unless using -p

Usage: $(basename "$0") [-d] [switches]
    -h              this help
    -d              decrypt
    -f file         act on file instead of stdin
    -o file         send output to file instead of stdout or if 
                    input file named "file" provided and encrypting, "file.aes",
                    if decrypting, "file.clear"
    -p descriptor   The numerical id (use 0 for stdin) to read the password
                    instead of stdin

Examples:

$0 -p3 ... 3<<<"password"
$0 -p3 ... 3<<<"\$(read -p 'pass: ' && echo $REPLY)"

EOF
}

encrypt=true
extension=".aes"
PASSWORD_FD=1

# leading ':' to run silent, 'f:' means f need an argument, 'h' is just an option
while getopts ":hdf:p:o:" opt; do case $opt in
    h)  usage; exit 0;;
    d)  encrypt=false; extension=".clear";;
    f)  SOURCE_FILE="${OPTARG}";;
    o)  TARGET_FILE="${OPTARG}";;
    p)  PASSWORD_FD="${OPTARG}";;
esac; done

if [[ -n "${SOURCE_FILE}" ]]; then
    # set target file if it is not set already to the requested source file with .aes at the end
    : ${TARGET_FILE:="${SOURCE_FILE}${extension}"}
else
    # set target file to stdout if not already set
    : ${TARGET_FILE:=/dev/stdout}
    SOURCE_FILE=/dev/stdin
fi

# grab password from stdin (file descriptor 0) or the one specified by user
if [[ -z "${PASSWORD_FD}" ]]; then read -u $(cat /dev/fd/${PASSWORD_FD}) PASSWORD; fi

if $encrypt; then
    # -e for encrypt, -p for print salt and iv
    3<<<"${PASSWORD}" openssl enc -e -p -pass fd:3 -in "${SOURCE_FILE}" -aes-256-cbc -base64 \
        | grep -v ^key | gzip \
        > "${TARGET_FILE}"
else
    gzip -dc "${SOURCE_FILE}" \
        | (read salt; read iv; 3<<<"${PASSWORD}" openssl enc -d -pass fd:3 -aes-256-cbc -base64) \
        > "${TARGET_FILE}"
fi


