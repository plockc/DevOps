#!/bin/bash

# USAGE: (run on the pi)
# bash <(curl -fsSL https://raw.github.com/plockc/DevOps/master/archInstall/picoInstall.sh)
#
# Will create a personal blog (public to read but private to write)

# abort if there is an error
set -e

#####################
# INSTALL PACKAGES
#####################

pacman --noconfirm -S --needed php-apc php-cgi lighttpd

#####################
# CONFIGURE PHP CACHE
#####################

sed -ibak 's/;extension=apc/extension=apc/' /etc/php/conf.d/apc*.ini # enable APC caching

####################
# CONFIGURE FASTCGI
####################

mkdir -p /etc/lighttpd/conf.d

# include fastcgi.conf
grep -q "conf.d/fastcgi.conf" /etc/lighttpd/lighttpd.conf \
   || (echo "include \"conf.d/fastcgi.conf\"" >> /etc/lighttpd/lighttpd.conf)

if [[ ! -f /etc/lighttpd/conf.d/fastcgi.conf ]]; then
	cat > /etc/lighttpd/conf.d/fastcgi.conf << EOF
	server.modules += ( "mod_fastcgi" )
	index-file.names += ( "index.php" )
	fastcgi.server = ( ".php" =>
		 ( "localhost" =>
		 ("socket" => "/run/lighttpd/php-fastcgi.sock",
				"bin-path" => "/usr/bin/php-cgi",
				"max-procs" => 1,
	            "bin-environment" => ("PHP_FCGI_CHILDREN" => "1"),
				"broken-scriptfilename" => "enable"
						 )
					   )
					)
EOF
fi

if [[ -d /usr/share/webapps/pico ]]; then
	echo Pico already installed
	exit
fi

####################
# INSTALL DOKUWIKI
####################

TMPDIR=$(mktemp -d)
curl "https://codeload.github.com/gilbitron/Pico/zip/master" > $TMPDIR/pico.zip
unzip $TMPDIR/pico.zip -d $TMPDIR
mkdir -p /usr/share/webapps
mv $TMPDIR/Pico-master /usr/share/webapps/pico
rm $TMPDIR/pico.zip
rmdir $TMPDIR
mkdir /usr/share/webapps/pico/cache


####################
# CONFIGURE DOKUWIKI
####################

# configure PHP so it is authorized to access the wiki installation
#sed -i'.bak' -e 's#\(^open_base.*\)#\1:/usr/share/webapps/pico#' /etc/php/php.ini

# include pico.conf
grep -q "conf.d/pico.conf" /etc/lighttpd/lighttpd.conf \
   || (echo "include \"conf.d/pico.conf\"" >> /etc/lighttpd/lighttpd.conf)

# create the dokuwiki configuration for lighttpd
test -f /etc/lighttpd/conf.d/pico.conf || cat > /etc/lighttpd/conf.d/pico.conf << EOF
server.modules += ( "mod_access", "mod_alias" )
alias.url += ("/pico" => "/usr/share/webapps/pico/")
static-file.exclude-extensions = ( ".php" )
\$HTTP["url"] =~ "/(\.|_)ht" { url.access-deny = ( "" ) }
\$HTTP["url"] =~ "^/pico/(lib|vendor)/+.*"  { url.access-deny = ( "" ) }
url.rewrite-once = (
    "^/pico/content/(.*)\.md" => "/pico/index.php"
)

url.rewrite-if-not-file = (
    "^/pico/(.*)$" => "/pico/index.php"
)
EOF

# create the dokuwiki local configuration if there is none
cp /usr/share/webapps/pico/config.php  /usr/share/webapps/pico/config.php.bak 2>/dev/null || true
cat > /usr/share/webapps/pico/config.php << EOF
<?php
\$config['site_title'] = "${wikiTitle}";
\$config['pages_order_by'] = 'date';            // Order pages by "alpha" or "date"
\$config['pages_order'] = 'asc';                // Order pages "asc" or "desc"
\$config['twig_config'] = array(			    // Twig settings
	'cache' => '/usr/share/webapps/pico/cache',	// To enable Twig caching change this to CACHE_DIR
	'autoescape' => false,				        // Autoescape Twig vars
	'debug' => false);					        // Enable Twig debug
?>
EOF

chown -R http:http /usr/share/webapps/pico

chmod 744 /usr/share/webapps/pico

systemctl enable lighttpd
systemctl start lighttpd

echo you can go to /wiki to view your blog