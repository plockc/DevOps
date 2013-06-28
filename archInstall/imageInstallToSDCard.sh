#!/bin/bash

# USAGE: sudo imageInstallToSDCard.sh <path to .img>

set -e

if (( `id -u` != 0 )); then
  echo Please run with sudo
  exit 1
fi

if [[ $# == 0 ]]; then echo && echo Please have the image path as the first argument && echo && exit; fi

if ! test -f "$1"; then echo && echo Image file $1 does not exist && echo && exit; fi

echo && read -p "Eject SD Card if it is inserted then hit enter to continue"

disksBefore=`diskutil list | awk '/^\/dev\/disk/ {print $0}'`

read -p "(Re)Insert SD Card, then hit enter to continue"

sleep 4 # allow the disk to be recognized

disksAfter=`diskutil list | awk '/^\/dev\/disk/ {print $0}'`

newDisk=`comm -3 <(echo $disksBefore | xargs -n 1 echo) <(echo $disksAfter | xargs -n 1 echo) | awk '{print $1}'`

if [[ $newDisk == "" ]]; then echo && echo No new disk found! && echo && exit; else echo && echo Found $newDisk; fi

newDiskEscaped=${newDisk//\//\\\/} # convert / to escaped slash: \/

echo
diskutil list \
  | awk "/^\/dev\/disk/ {record=0} \
     "/$newDiskEscaped/' {record=1} \
     {if (record) diskDetail = diskDetail $0  "\n"} \
     END {print diskDetail}'
echo
read -p "Are you sure you want to destroy $newDisk and all of its partitions with the contents of $1 [yN]?"

if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo Aborting
    exit 1;
fi

rawDisk=${newDisk/disk/rdisk} # use the raw disk to avoid the buffering, much faster

sudo diskutil unmountDisk $newDisk

echo && echo Copying Image, this will take about a minute per GB on a class 10 card
sudo dd bs=16m if="$1" of=$rawDisk

#######################
## NOW RESIZE PARTITION
#######################

sleep 5 # some reason doing it right away fails

echo Completed Image Copy, unmounting Disk to prepare for resizing partition
sudo diskutil unmountDisk $newDisk

sleep 5 # allow disk to unmount

totalDiskBlocks=`diskutil info $newDisk | grep "Total Size" | sed 's/.*exactly \([0-9]*\) 512-Byte-Blocks)/\1/'`

startBlock=`(sudo fdisk -e $newDisk 2>/dev/null <<EOF
print
quit
EOF
) | grep "^ 2" | awk '{print $11}'`

let newSize=$totalDiskBlocks-$startBlock

let newSizeReadable=$totalDiskBlocks*512/1024/1024

# update the partition table with the same start and new size for partition 2
sudo fdisk -e $newDisk 2>/dev/null <<EOF
edit 2


$startBlock
$newSize
write
quit
EOF

echo && echo "Updated partition table, results:" && echo

sudo fdisk $newDisk

echo && echo Ejecting

sleep 4
sudo diskutil eject $newDisk

echo
echo 1\) Remove the SD Card and install to the Raspberry Pi
echo 2\) Connect your Pi to the network and boot it
echo 3\) wait about 25 seconds for the host to appear in local dns
echo 4\) \"arp -a \| grep alarmpi\" to get IP address
echo 5\) "ssh root@<ip address>" with the default password 'root'
echo
