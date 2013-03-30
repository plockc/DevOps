#!/bin/bash

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

pacstrap /mnt base base-devel openssh php-apc php-cgi php-fpm php-sqlite lighttpd dokuwiki augeas wget unzip


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
systemctl enable dhcpcd@eth0.service
exit # exit the chroot
EOF

# umount /mnt/{boot,} 
# reboot
