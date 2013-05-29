#!/bin/bash

# USAGE: bash <(curl -fsSL https://raw.github.com/plockc/ArchDevOps/master/archInstall/archInstall.sh)

# TODO: request for hostname and for a initial password
# TODO: options for a Arch package cache, or personal wiki/blog, or something else

set -e

pacman -Sy php-apc php-cgi php-sqlite lighttpd dokuwiki augeas darkstat unzip dnsutils rsync

echo "doku.plock.org" > /etc/hostname
ln -s /usr/share/zoneinfo/US/Pacific /etc/localtime
systemctl enable darkstat lighttpd.service

chpasswd -e << EOSF
root:\$6\$BcIn6ZXm\$dsIT5df3t.iNCQUbYMTVMuublLUUC0s4RjUknQfIPYtvpGlivPH9Srq4Ho/Oh1n/PoLuNHiH/C7O4nb6JC55A.
EOSF
