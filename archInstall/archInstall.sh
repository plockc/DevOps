#!/bin/bash

# USAGE: bash <(curl -fsSL https://raw.github.com/plockc/ArchDevOps/master/archInstall/archInstall.sh)

# TODO: options for a Arch package cache

set -e

# set the clock
pacman --noconfirm -Syy --needed ntp && ntpd -gq && hwclock -w

# confirm that we want to destroy /dev/sda completely
echo Checking mounts . . .
cat /proc/mounts | grep sda && (echo Error, /dev/sda is used) || echo /dev/sda does not appear to be used
read -p "Are you sure you want to completely wipe /dev/sda? " -r
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo Aborting
    exit;
fi

######################################
# GET A NEW ROOT PASSWORD
######################################
read -s -p "Please enter a new root password: "
NEW_PASSWORD=$REPLY
echo
read -s -p "Please confirm: "
echo

if [[ ! $REPLY == $NEW_PASSWORD ]]
then
  echo Passwords did not match, please try again
  exit;
fi

######################################
## GET NEW HOSTNAME
######################################
read -p "Please enter the full host name for this Arch Linux instance: "
NEW_HOSTNAME=$REPLY
if [[ $NEW_HOSTNAME == "" ]]
then
echo Please try again with a valid host name
exit;
fi
HOSTNAME=$NEW_HOSTNAME

######################################
# CREATE PARTITIONS AND FILESYSTEMS
######################################
parted --script --align optimal -- /dev/sda \
  mklabel msdos \
  mkpart primary ext4 1 100M \
  mkpart primary ext4 100M -1G \
  mkpart primary linux-swap -1G -1s
partprobe /dev/sda

mkfs.ext4 -q /dev/sda2
mount -t ext4 /dev/sda2 /mnt

mkfs.ext4 -q /dev/sda1
mkdir -p /mnt/boot
mount -t ext4 /dev/sda1 /mnt/boot

# this does not seem to be working all the way
mkswap /dev/sda3

######################################
# INSTALL PACKAGES
######################################
pacstrap /mnt base base-devel openssh augeas ntp wget darkhttpd darkstat unzip dnsutils rsync dtach tmux

######################################
# BASIC CONFIGURATION
######################################
genfstab -p /mnt >> /mnt/etc/fstab
echo "/dev/sda3   swap   swap   defaults   0   0" >> /mnt/etc/fstab

ln -s /usr/share/zoneinfo/US/Pacific /mnt/etc/localtime

echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
sed -i.bak 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /mnt/etc/locale.gen

echo $NEW_HOSTNAME > /mnt/etc/hostname

echo "export http_proxy='$http_proxy'" > /mnt/etc/profile.d/pacmanProxy.sh

#################
# RUN SCRIPTS
#################
arch-chroot /mnt <<EOF

mkinitcpio -p linux

pacman --noconfirm -S syslinux

sed -i 's/sda3/sda2/' /boot/syslinux/syslinux.cfg
syslinux-install_update -iam # install files(-i), set boot flag (-a), install MBR boot code (-m)

locale-gen # edit /etc/locate.gen possibly
systemctl enable sshd.service darkstat ntpd.service dhcpcd

## CHANGE ROOT PASSWORD
chpasswd << EOSF
root:$NEW_PASSWORD
EOSF

exit # exit the chroot
EOF

umount /mnt/{boot,} 
reboot
