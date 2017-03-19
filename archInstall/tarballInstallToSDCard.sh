#!/bin/bash

# USAGE: sudo imageInstallToSDCard.sh [path to tarball of Arch disto, if not ArchLinuxARM-rpi-2-latest.tar.gz>

set -e

if [[ "$SUDO_USER" == "" ]]; then echo "run with sudo please"; exit 1; fi

if (( `id -u` != 0 )); then echo Please run with sudo; exit 1; fi

if [[ $# > 1 ]]; then printf "\nPlease only have the image path as the first argument\n"; exit 1; fi

# default to file in directory
TARBALL="${1-ArchLinuxARM-rpi-2-latest.tar.gz}"

if ! test -f "$TARBALL"; then printf "\nImage file "$1" does not exist\n"; exit 1; fi

##############
# Verify new hostname
##############

if [[ "$NEWHOSTNAME" == "" ]]; then
    echo "You must set a new hostname with environment variable NEWHOSTNAME"
    exit 1
fi
# this will be put into /etc/hostname by the init script

###############
# Get new root password
###############

newpass=$(openssl rand -base64 12 | tr -d '+/=' | head -c10)
NEWPASS=$(openssl passwd -1 $newpass)

###############
# Figure out SD Card
###############

disksBefore=$(diskutil list | awk '/^\/dev\/disk/ {print $0}')

echo "Insert or Eject then re-insert SD Card, if disk is not recognized, then Ctrl-C to quit"

# keep looking for new disks coming on-line, filtering disks that go away, and check that it is an SD card
while [ -z ${newDisk+x} ]; do
  disksAfter=$(diskutil list | awk '/^\/dev\/disk/ {print $0}')
  newDisks=$(diff --unified=0 <(echo "$disksBefore") <(echo "$disksAfter") | sed '1,2d;/^+/!d;s/^+//')
  if [[ $newDisks == "" ]]; then
    printf ".";
  else 
    echo "Found disks $newDisks"
    # input redirected at the end allows for newDisk assignment in this while loop to be in scope 
    while read; do
          diskInfo=$(diskutil info $REPLY | grep "Device / Media Name")
          if egrep -q "Generic.*SD|APPLE SD Card Reader Media" <<<"$diskInfo"; then
            echo $REPLY is an SD card
            newDisk=$REPLY
   	  else
            echo $REPLY does not appear to be an SD card, it was $diskInfo
          fi
    done <<<"${newDisks}"
  fi
  disksBefore="$disksAfter"
  sleep 1;
done

echo

newDiskEscaped=${newDisk//\//\\\/} # convert / to escaped slash: \/

#####################################
# Print disk details and confirm wipe
#####################################

diskutil list \
  | awk "/^\/dev\/disk/ {record=0} \
     "/$newDiskEscaped/' {record=1} \
     {if (record) diskDetail = diskDetail $0  "\n"} \
     END {print diskDetail}'
echo
read -p "Are you sure you want to DESTROY $newDisk and all of its partitions with the contents of $TARBALL [yN]?"

if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo Aborting
    exit 1;
fi

#############################
# Partition Disk
#############################
echo
echo Unmounting Disk $newDisk in preparation for repartitioning and formatting
sudo diskutil unmountDisk $newDisk

diskutil partitionDisk $newDisk MBR fat32 BOOT 350M fat32 REFORMAT R >/dev/null 2>/dev/null

printf "\nUpdated partition table, results:\n"

fdisk $newDisk

############################
# Setup /boot
############################
mountPoint=$(diskutil info ${newDisk}s1 | sed '/Mount Point/!d;s/.*:[ ]*\(.*\)/\1/')

echo Copying bootstrap files from $TARBALL:/boot to mouned ${newDisk}  at "${mountPoint}"
bsdtar -xpf "$TARBALL" --strip-components 2 -C "${mountPoint}/" boot

###########################
# Create initramfs
###########################

echo Setting up initramfs 
mkdir -p RAMFS/{bin,dev,proc,dev,mnt,newroot,etc,run/systemd} 
cp -a /dev/{null,tty,zero,console} RAMFS/dev
(cd RAMFS; ln -s usr/lib/ lib)

echo "  Unpacking some utilities and library dependencies for initramfs"
tar -zxf "$TARBALL" -C RAMFS \
  ./usr/bin/{fdisk,chroot,cat,ln,ls,cp,mkfs.ext4,reboot,systemctl,bash,sed,tar,bsdtar,{u,}mount,echo,mkdir,chmod,setsid,sync,sleep,dhcpcd} \
  ./usr/lib/lib{readline,ncursesw,mount,acl,attr,dl{,-2.\*},c,c-2\*,uuid,smartcols,blkid,ext2fs,com_err,e2p}.so\* \
  ./usr/lib/lib{gcc_s,cap,pthread,crypto,expat,lzo2,lzma,lz4,gcrypt,gpg-error,rt,rt-2\*,bz2,z,pthread-2.\*}.so\* \
  ./usr/lib/{ld-linux{-armhf,},ld-2.\*}.so\* 

echo "Copying $TARBALL into BOOT partition at ${mountPoint}"
cp "$TARBALL" "${mountPoint}"

#######################################
# Create init for one time installation
#######################################

echo "Creating /init"

cat > "RAMFS/init" <<INITEOF
#!/usr/bin/bash

mount -t devtmpfs devtmpfs /dev
mount -t proc proc /proc
# takes a moment for devices to appear
sleep 3
# mount the BOOT partition read only, the arch linux distribution file is here
mount -r -t vfat /dev/mmcblk0p1 /mnt


sync
umount /mnt

echo Changing second partition to Linux
echo -e "t\n2\n83\nw" | /usr/bin/fdisk /dev/mmcblk0 > /dev/null

echo Formatting Second partition to ext4
mkfs.ext4 -q -F -L ROOT /dev/mmcblk0p2

echo Mounting second partition
mount -t ext4 /dev/mmcblk0p2 /newroot

echo Unpacking Arch Linux Distribution, will take a couple minutes
mount -t vfat /dev/mmcblk0p1 /mnt
bsdtar -zxf /mnt/$TARBALL -C newroot 

echo Restoring original cmdline.txt and config.txt for normal booting
cp /mnt/cmdline.txt.bak /mnt/cmdline.txt
cp /mnt/config.txt.bak /mnt/config.txt
# and fix hdmi
echo "hdmi_safe=1" >> "${mountPoint}/config.txt"

echo Linking libraries for current init script
for f in \$(ls -1 /newroot/usr/lib); do ln -s /newroot/usr/lib/\$f /usr/lib; done

###############
# Create setup script within new root directory
###############
cat > /newroot/setup.sh <<SETUPEOF
echo loading hardware random 
modprobe bcm2708-rng

# configure networking
ip link set dev eth0 up
dhcpcd eth0

newtimezone=$(systemsetup -gettimezone | sed 's/.*: \(.*\)/\1/')
echo linking time to \$newtimezone
ln --force -s /usr/share/zoneinfo/\$newtimezone /etc/localtime

echo setting hostname to $NEWHOSTNAME
echo $NEWHOSTNAME > /etc/hostname

#******************** REPLACE WITH FIXED SETTING OF TIME
echo setting hardware clock
pacman -Sy --needed --noconfirm ntp
ntpd -gq

echo setting up pacserve
#pacman -Sy --noconfirm archlinux-keyring
#pacman-key --init
# maybe not needed - pacman-key --refresh-keys
#pacman --populate archlinux
#cat >> /etc/pacman.conf <<EOF
#[xyne-any]
#SigLevel = Required
#Server   = http://xyne.archlinux.ca/repos/xyne
#EOF
#pacman --noconfirm -Sy pacserve
#systemctl enable pacserve.service

#systemctl start pacserve.service
#pacsrv --noconfirm -Sy --needed darkhttpd unzip dnsutils rsync screen git dtach vim xorg-server xf86-video-dbturbo-git xorg-init xterm i3 ttf-dejavu chromium alsa-utils
pacman --noconfirm -Sy --needed darkhttpd unzip dnsutils rsync screen git dtach vim xorg-server xf86-video-dbturbo-git xorg-init xterm i3 ttf-dejavu chromium alsa-utils

echo adding user
useradd -m -G wheel -s /bin/bash $SUDO_USER
mkdir -m 700 -p /home/$SUDO_USER/.ssh
cat > /home/$SUDO_USER/.ssh/authorized_keys <<KEYEOF
$(cat /home/$SUDO_USER/.ssh/id-rsa.pub)
KEYEOF
chown $SUDO_USER:$SUDO_USER /home/$SUDO_USER/.ssh/authorized_keys

echo setting root password to something random
chpasswd -e <<EOF
root:$NEWPASS
EOF

SETUPEOF

chmod +x /newroot/setup.sh

##################
# Chroot and run setup
##################
echo chroot-ing for more setup
cd /newroot
mount -t proc /proc proc
mount --rbind /dev dev
mount --rbind /run run
chroot /newroot /setup.sh

echo Spawning user shell, after exiting, system will reboot into Arch Linux
setsid /usr/bin/bash -c 'PATH=\$PATH:/newroot/usr/bin exec /usr/bin/bash </dev/tty1 >/dev/tty1 2>&1'

sync
umount -a

echo rebooting in 5 seconds . . .
reboot --no-wtmp --no-wall -d 5 --force
sleep 1
INITEOF

chmod +x "RAMFS/init"

############
# Create initramfs
############
echo Creating ${mountPoint}/initramfs.gz 
cd RAMFS; sudo bash -c "find . | cpio -oHnewc | gzip > \"${mountPoint}/initramfs.gz\""; cd ..


cp "${mountPoint}/cmdline.txt" "${mountPoint}/cmdline.txt.bak"
echo "root=/dev/mmcblk0p1 rw rootwait console=ttyAMA0,115200 console=tty1 selinux=0 plymouth.enable=0 smsc95xx.turbo_mode=N dwc_otg.lpm_enable=0 elevator=noop initrd=0x01f00000 init=init" > "${mountPoint}/cmdline.txt"
cp "${mountPoint}/cmdline.txt" "${mountPoint}/cmdline.txt.new"

cp "${mountPoint}/config.txt" "${mountPoint}/config.txt.bak"
echo "initramfs initramfs.gz 0x01f00000" >> "${mountPoint}/config.txt"
echo "hdmi_safe=1" >> "${mountPoint}/config.txt"
echo "hdmi_mod=85" >> "${mountPoint}/config.txt"
cp "${mountPoint}/config.txt" "${mountPoint}/config.txt.new"

##################
# CLEANUP
##################
echo && echo Ejecting SD Card

sync
sudo diskutil eject $newDisk

echo cleaning up scratch directory
rm -r RAMFS

echo
echo Install card in to raspberry pi and boot, you can check for alarmpi on the network, default password for root is "root"
echo
