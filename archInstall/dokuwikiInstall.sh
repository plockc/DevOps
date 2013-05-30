#!/bin/bash

# abort if there is an error
set -e

#####################
# CONFIGURE PHP CACHE
#####################

sed -ibak 's/;extension=apc.so/extension=apc.so/' /etc/php/conf.d/apc.ini # enable APC caching

####################
# CONFIGURE LIGHTTPD
####################

mkdir -p /etc/lighttpd/conf.d

# include fastcgi.conf
grep "conf.d/fastcgi.conf" /etc/lighttpd/lighttpd.conf \
   || echo "include \"conf.d/fastcgi.conf\"" >> /etc/lighttpd/lighttpd.conf

if ! test -f /etc/lighttpd/conf.d/fastcgi.conf; then
	cat > /etc/lighttpd/conf.d/fastcgi.conf << EOF
	server.modules += ( "mod_fastcgi" )
	index-file.names += ( "index.php" )
	fastcgi.server = ( ".php" =>
					   ( "localhost" =>
						 (
						   "socket" => "/run/lighttpd/php-fastcgi.sock",
						   "bin-path" => "/usr/bin/php-cgi",
						   "max-procs" => 1,
	"bin-environment" => (
	"PHP_FCGI_CHILDREN" => "1"
	),
						   "broken-scriptfilename" => "enable"
						 )
					   )
					)
	EOF
fi
