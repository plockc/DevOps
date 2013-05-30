#!/bin/bash

# USAGE: bash <(curl -fsSL https://raw.github.com/plockc/ArchDevOps/master/archInstall/archInstall.sh)

# TODO: options for a Arch package cache

set -e

cat /proc/mounts | grep sda && (echo Error, /dev/sda is used) || echo /dev/sda does not appear to be used
read -p "Are you sure you want to destroy /dev/sda? " -r
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo Aborting
    exit;
fi

pacman --noconfirm -Syy ntp && ntpd -gq && hwclock -w

parted --script --align optimal /dev/sda \
  mklabel msdos \
  mkpart primary ext4 63s 100MB \
  mkpart primary ext4 100MB 20GB \
  mkpart primary linux-swap 20GB 21GB

partprobe /dev/sda

mkfs.ext4 -q /dev/sda2
mount -t ext4 /dev/sda2 /mnt

mkfs.ext4 -q /dev/sda1
mkdir -p /mnt/boot

mount -t ext4 /dev/sda1 /mnt/boot

mkswap /dev/sda3
swapon /dev/sda3

pacstrap /mnt base base-devel openssh augeas ntp wget darkhttpd darkstat unzip dnsutils rsync screen

genfstab -p /mnt >> /mnt/etc/fstab

arch-chroot /mnt <<EOF
mkinitcpio -p linux
pacman --noconfirm -S syslinux

sed -i 's/sda3/sda2/' /boot/syslinux/syslinux.cfg
syslinux-install_update -iam # install files(-i), set boot flag (-a), install MBR boot code (-m)

ln -s /usr/share/zoneinfo/US/Pacific /etc/localtime
echo LANG=en_US.UTF-8 > /etc/locale.conf
locale-gen # edit /etc/locate.gen possibly
#systemctl enable dhcpcd@enp0s5
# install network device is eth0 but runtime is emp0s5, so have to do it manually
ln -s '/usr/lib/systemd/system/dhcpcd\@.service' '/etc/systemd/system/multi-user.target.wants/dhcpcd\@enp0s5.service'
systemctl enable sshd.service darkstat ntpd.service

## CHANGE ROOT PASSWORD

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
chpasswd << EOSF
root:$NEW_PASSWORD
EOSF

## CHANGE HOSTNAME
read -p "Please enter the full host name for this Pi: "
HOSTNAME=$REPLY
if [[ $HOSTNAME == "" ]]
then
echo Please try again with a valid host name
exit;
fi
echo $HOSTNAME > /etc/hostname


exit # exit the chroot
EOF

umount /mnt/{boot,} 
reboot
