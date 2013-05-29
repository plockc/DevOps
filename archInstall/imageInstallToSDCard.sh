set -e

echo && read -p "Eject SD Card if it is inserted then hit enter to continue"

disksBefore=`diskutil list | awk '/^\/dev\/disk/ {print $0}'`

read -p "(Re)Insert SD Card then hit enter to continue"

disksAfter=`diskutil list | awk '/^\/dev\/disk/ {print $0}'`

newDisk=`comm -3 <(echo $disksBefore | xargs -n 1 echo) <(echo $disksAfter | xargs -n 1 echo) | awk '{print $1}'`

if [[ $newDisk == "" ]]; then echo && echo No new disk found! && echo && exit; else echo echo Found $newDisk; fi

newDiskEscaped=${newDisk//\//\\\/} # convert / to escaped slash: \/

echo
diskutil list | awk "/^\/dev\/disk/ {record=0} "/$newDiskEscaped/' {record=1} {if (record) diskDetail = diskDetail $0  "\n"} END {print diskDetail}'
echo
read -p "Are you sure you want to destroy $newDisk with the contents of $0 ? "

if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo Aborting
    exit;
fi

echo sudo dd bs=1m if=$0 of=$newDisk
echo sudo diskutil unmountDisk $newDisk
