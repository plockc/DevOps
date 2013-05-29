#!/bin/bash

set -e

if [[ $# == 0 ]]; then echo && echo Please have the image path as the first argument && echo && exit; fi

if ! test -f "$1"; then echo && echo Image file $1 does not exist && echo && exit; fi

echo && read -p "Eject SD Card if it is inserted then hit enter to continue"

disksBefore=`diskutil list | awk '/^\/dev\/disk/ {print $0}'`

read -p "(Re)Insert SD Card then hit enter to continue"

disksAfter=`diskutil list | awk '/^\/dev\/disk/ {print $0}'`

newDisk=`comm -3 <(echo $disksBefore | xargs -n 1 echo) <(echo $disksAfter | xargs -n 1 echo) | awk '{print $1}'`

if [[ $newDisk == "" ]]; then echo && echo No new disk found! && echo && exit; else echo && echo Found $newDisk; fi

newDiskEscaped=${newDisk//\//\\\/} # convert / to escaped slash: \/

echo
diskutil list | awk "/^\/dev\/disk/ {record=0} "/$newDiskEscaped/' {record=1} {if (record) diskDetail = diskDetail $0  "\n"} END {print diskDetail}'
echo
read -p "Are you sure you want to destroy $newDisk with the contents of $1 ? [yN] "

if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo Aborting
    exit;
fi

newDisk=${newDisk/disk/rdisk} # use the raw disk to avoid the buffering, much faster
sudo diskutil unmountDisk $newDisk
echo && echo Copying Image, this will take a while
sudo dd bs=16m if="$1" of=$newDisk
