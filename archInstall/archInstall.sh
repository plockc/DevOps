#!/bin/bash

# USAGE: bash <(curl -fsSL https://raw.github.com/plockc/ArchDevOps/master/archInstall/archInstall.sh)

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
  mkpart primary ext4 100MB 3GB \
  mkpart primary linux-swap 3GB 4GB

partprobe /dev/sda

mkfs.ext4 -q /dev/sda2
mount -t ext4 /dev/sda2 /mnt

mkfs.ext4 -q /dev/sda1
mkdir -p /mnt/boot

mount -t ext4 /dev/sda1 /mnt/boot

mkswap /dev/sda3
swapon /dev/sda3

pacstrap /mnt base base-devel openssh php-apc php-cgi php-fpm php-sqlite lighttpd dokuwiki augeas ntp wget unzip


genfstab -p /mnt >> /mnt/etc/fstab

arch-chroot /mnt <<EOF
mkinitcpio -p linux
pacman --noconfirm -S syslinux

sed -i 's/sda3/sda2/' /boot/syslinux/syslinux.cfg
syslinux-install_update -iam # install files(-i), set boot flag (-a), install MBR boot code (-m)

echo "doku.plock.org" > /etc/hostname
ln -s /usr/share/zoneinfo/US/Pacific /etc/localtime
echo LANG=en_US.UTF-8 > /etc/locale.conf
locale-gen # edit /etc/locate.gen possibly
#systemctl enable dhcpcd@enp0s5
# install network device is eth0 but runtime is emp0s5, so have to do it manually
ln -s '/usr/lib/systemd/system/dhcpcd\@.service' '/etc/systemd/system/multi-user.target.wants/dhcpcd\@enp0s5.service'
systemctl enable sshd.service
systemctl enable lighttpd.service
systemctl enable ntpd.service

chpasswd -e << EOSF
root:$6$BcIn6ZXm$dsIT5df3t.iNCQUbYMTVMuublLUUC0s4RjUknQfIPYtvpGlivPH9Srq4Ho/Oh1n/PoLuNHiH/C7O4nb6JC55A.
EOSF

exit # exit the chroot
EOF

umount /mnt/{boot,} 
reboot
