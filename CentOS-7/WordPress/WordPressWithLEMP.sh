#!/bin/sh

#Install Components of LEMP Stack
yum -y install epel-release
yum -y install unzip nginx php-fpm php-mysql mariadb-server mariadb

#Download WordPress and configure
wget https://wordpress.org/latest.zip -O /tmp/wordpress.zip
unzip /tmp/wordpress.zip -d /tmp/
cp /tmp/wordpress/wp-config-sample.php /tmp/wordpress/wp-config.php

#Generate MySQL Passwords and write them to file
ROOTMYSQLPASS=`dd if=/dev/urandom bs=1 count=12 2>/dev/null | base64 -w 0 | rev | cut -b 2- | rev`
WPMYSQLPASS=`dd if=/dev/urandom bs=1 count=12 2>/dev/null | base64 -w 0 | rev | cut -b 2- | rev`
echo "Root MySQL Password $ROOTMYSQLPASS" > /root/passwords.txt
echo "Wordpress MySQL Password $WPMYSQLPASS" >> /root/passwords.txt

#Configure WordPress with DB Credentials and Secure Salts
sed -i -e "s/database_name_here/wordpress/" /tmp/wordpress/wp-config.php
sed -i -e "s/username_here/wordpress/" /tmp/wordpress/wp-config.php
sed -i -e "s/password_here/$WPMYSQLPASS/" /tmp/wordpress/wp-config.php
for i in `seq 1 8`; do wp_salt=$(</dev/urandom tr -dc 'a-zA-Z0-9!@#$%^&*()\-_ []{}<>~`+=,.;:/?|' | head -c 64 | sed -e 's/[\/&]/\\&/g'); sed -i "0,/put your unique phrase here/s/put your unique phrase here/$wp_salt/" /tmp/wordpress/wp-config.php; done

#Start MariaDB and enable to start automatically on boot
systemctl enable mariadb
systemctl start mariadb

#Create new WordPress user and assign password to root and the wordpress user generated above
/usr/bin/mysqladmin -u root -h localhost create wordpress
/usr/bin/mysqladmin -u root -h localhost password $ROOTMYSQLPASS
/usr/bin/mysql -uroot -p$ROOTMYSQLPASS -e "CREATE USER wordpress@localhost IDENTIFIED BY '"$WPMYSQLPASS"'"
/usr/bin/mysql -uroot -p$ROOTMYSQLPASS -e "GRANT ALL PRIVILEGES ON wordpress.* TO wordpress@localhost"

#Configure Nginx with WordPress
mkdir -p /var/www/html
sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" /etc/php.ini
sed -i -e "s|listen = 127.0.0.1:9000|listen = /var/run/php-fpm/php-fpm.sock|" /etc/php-fpm.d/www.conf
sed -i -e "s|user = apache|user = nginx|" /etc/php-fpm.d/www.conf
sed -i -e "s|group = apache|group = nginx|" /etc/php-fpm.d/www.conf
cp -Rf /tmp/wordpress/* /var/www/html/.
chown -Rf nginx.nginx /var/www/html/*
rm -f /var/www/html/index.html
rm -Rf /tmp/wordpress*

#Write below config to nginx.conf

cat > /etc/nginx/nginx.conf << "EOF"
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;
events {
    worker_connections 1024;
}
http {
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent" "$http_x_forwarded_for"';
    access_log  /var/log/nginx/access.log  main;
    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 2048;
    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;
    # Load modular configuration files from the /etc/nginx/conf.d directory.
    # See http://nginx.org/en/docs/ngx_core_module.html#include
    # for more information.
    include /etc/nginx/conf.d/*.conf;
}
EOF

#Write a Default Config for our WordPress installation 

cat > /etc/nginx/conf.d/default.conf << "EOF"
server {
  listen 80 default_server;
  listen [::]:80 default_server ipv6only=on;
  root /var/www/html;
  index index.php index.html index.htm;
  server_name localhost;
  location / {
      # First attempt to serve request as file, then
      # as directory, then fall back to displaying a 404.
      try_files $uri $uri/ =404;
      # Uncomment to enable naxsi on this location
      # include /etc/nginx/naxsi.rules
  }
  error_page 404 /404.html;
  error_page 500 502 503 504 /50x.html;
  location = /50x.html {
      root /usr/share/nginx/html;
  }
  location ~ \.php$ {
      try_files $uri =404;
      fastcgi_split_path_info ^(.+\.php)(/.+)$;
      fastcgi_pass unix:/var/run/php-fpm/php-fpm.sock;
      fastcgi_index index.php;
      fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
      include fastcgi_params;
  }
}
EOF

#Start,Restart and Enable some services to start on boot 
systemctl start php-fpm
systemctl enable php-fpm.service
systemctl enable nginx.service
systemctl restart nginx