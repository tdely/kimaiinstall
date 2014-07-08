#!/bin/bash

# General settings
domain=$1
kimaiversion="0.9.3-rc.1"
webdir="/var/www"
passlength=15

# Nginx Settings
workrlimit=1023
workproc=$( nproc )
let workconn=${workrlimit}/${workproc}

# Applications to install
applist=( curl nginx php5-fpm php-apc mysql-server php5-mysqlnd )

function echo_failure {
    echo -ne "[\e[31mFAILED\e[0m]\n"
}
function echo_success {
    echo -ne "[\e[32m  OK  \e[0m]\n"
}
function status_message {
    echo -ne "[      ] $1\r"
}
function check_error_exit {
    if [ ! -z "$1" ]; then
        echo " -> $1"
        exit 1
    fi
}

# Make sure domain was given
if [ -z "${domain}" ]; then
    echo "You must specify a domain for Kimai"
    exit 1
fi

# Sanity check
status_message "Sanity check to see if APT is installed and usable"
command -v apt-get >/dev/null 2>&1 \
  || { echo_failure; exit 1; }
echo_success

# Update APT
echo "Updating APT.."
apt-get update \
  || { echo -e >&2 "apt-get \e[31mfailed\e[0m to update"; exit 1; }

# Install applications
echo "Installing required applications.."
for item in "${applist[@]}"
do
    apt-get install "${item}" -y \
      || { echo -e >&2 "apt-get \e[31mfailed\e[0m on ${item}"; exit 1; }
done

# Create /var/www
echo "Checking if ${webdir} exists.."
if [ ! -d "${webdir}" ]; then
    echo "Not found"
    status_message "Creating directory"
    ERROR=$( mkdir "${webdir}" 2>&1 ) \
      || echo_failure
    check_error_exit "${ERROR}"
    echo_success
else
    echo "Found"
fi

# Download Kimai
echo "Checking if Kimai is already downloaded.."
if [ ! -f "/tmp/kimai-v${kimaiversion}.tar.gz" ]; then
    echo "Not found"
    echo "Downloading Kimai ${kimaiversion}"
    curl "https://github.com/kimai/kimai/archive/v${kimaiversion}.tar.gz" \
      -\#Lo "/tmp/kimai-v${kimaiversion}.tar.gz" \
      || exit 1
else
    echo "Found"
fi

# Extract archive
status_message "Extracting archive"
ERROR=$( tar -xzf "/tmp/kimai-v${kimaiversion}.tar.gz" -C "${webdir}" 2>&1 ) \
  || echo_failure
check_error_exit "${ERROR}"
echo_success

# Set ownership
status_message "Setting ownership of Kimai"
ERROR=$( chown -R "www-data:www-data" \
           "/var/www/kimai-${kimaiversion}" 2>&1 ) \
  || echo_failure
check_error_exit "${ERROR}"
echo_success

# Set permissions
status_message "Setting permissions on Kimai"
ERROR=$( find "/var/www/kimai-${kimaiversion}" \
           -type d -exec chmod 0550 {} \; 2>&1 ) \
  || echo_failure
check_error_exit "${ERROR}"
ERROR=$( find "/var/www/kimai-${kimaiversion}" \
           -type f -exec chmod 0440 {} \; 2>&1 ) \
  || echo_failure
check_error_exit "${ERROR}"
ERROR=$( chmod 0770 "/var/www/kimai-${kimaiversion}/core/temporary" 2>&1 ) \
  || echo_failure
check_error_exit "${ERROR}"
ERROR=$( chmod 0660 "/var/www/kimai-${kimaiversion}/core/temporary/logfile.txt" 2>&1 ) \
  || echo_failure
check_error_exit "${ERROR}"
ERROR=$( chmod 0770 "/var/www/kimai-${kimaiversion}/core/includes" 2>&1 ) \
  || echo_failure
check_error_exit "${ERROR}"
echo_success

# Configure Nginx
status_message "Writing configuration to /etc/nginx.conf"
ERROR=$(( echo "\
user                        www-data;
worker_processes            ${workproc};
worker_priority             15;
worker_rlimit_nofile        ${workrlimit};
pid                         /var/run/nginx.pid;

events {
  worker_connections        ${workconn};
  accept_mutex              on;
  multi_accept              off;
}

http {
  client_body_timeout       5s;
  client_header_timeout     5s;
  keepalive_timeout         75s;
  send_timeout              15s;
  charset                   utf-8;
  include                   /etc/nginx/mime.types;
  default_type              application/octet-stream;
  gzip                      on;
  gzip_disable              'msie6';
  gzip_vary                 on;
  gzip_proxied              any;
  ignore_invalid_headers    on;
  keepalive_requests        50;
  keepalive_disable         none;
  max_ranges                1;
  msie_padding              off;
  open_file_cache           max=1000 inactive=2h;
  open_file_cache_errors    on;
  open_file_cache_min_uses  1;
  open_file_cache_valid     1h;
  output_buffers            1 512;
  postpone_output           1440;
  read_ahead                512K;
  recursive_error_pages     on;
  reset_timedout_connection on;
  sendfile                  on;
  server_tokens             off;
  server_name_in_redirect   off;
  source_charset            utf-8;
  tcp_nodelay               on;
  tcp_nopush                off;

  upstream php5-fpm {
    server unix:/var/run/php5-fpm.sock;
  }

  include                   /etc/nginx/conf.d/*.conf;
  include                   /etc/nginx/sites-enabled/*;
}" 1> /etc/nginx/nginx.conf ) 2>&1 ) \
  || _failure
check_error_exit "${ERROR}"
echo_success

# Setup Kimai site
status_message "Writing site configuration to /etc/nginx/sites-available/kimai"
ERROR=$(( echo -e "\
server {
  root        /var/www/kimai-${kimaiversion}/core;
  index       index.html index.htm index.php;

  server_name ${domain}
  listen      80;

  add_header  X-Frame-Options 'DENY';

  location  / {
    try_files \$uri \$uri/ =404;
  }

  location ~ \\.php\$ {
    fastcgi_split_path_info ^(.+\\.php)(/.+)\$;
    fastcgi_pass php5-fpm;
    fastcgi_intercept_errors on;
    fastcgi_index index.php;
    include fastcgi_params;
  }
}" 1> /etc/nginx/sites-available/kimai ) 2>&1 ) \
  || echo_failure
check_error_exit "${ERROR}"
echo_success

# Disable default site
status_message "Disabling default site"
ERROR=$( if [ -x "/etc/nginx/sites-enabled/default" ]; then \
             rm "/etc/nginx/sites-enabled/default" 2>&1; fi ) \
  || echo_failure
check_error_exit "${ERROR}"
echo_success

# Enable Kimai site
status_message "Enabling Kimai site"
ERROR=$(( rm "/etc/nginx/sites-enabled/kimai" >/dev/null 2>&1 ) \
  ; ln -s "/etc/nginx/sites-available/kimai" \
          "/etc/nginx/sites-enabled/kimai" 2>&1 ) \
  || echo_failure
check_error_exit "${ERROR}"
echo_success

# Configure PHP-FPM
status_message "Configuring PHP-FPM"
ERROR=$(( sed -i 's/;listen = .*/listen = \/var\/run\/php5-fpm.sock/g' \
  /etc/php5/fpm/pool.d/www.conf && \
sed -i 's/;listen\.owner.*/listen.owner = www-data/g' \
  /etc/php5/fpm/pool.d/www.conf && \
sed -i 's/;listen\.group.*/listen.group = www-data/g' \
  /etc/php5/fpm/pool.d/www.conf && \
sed -i 's/;listen\.mode.*/listen.mode = 0660/g' \
  /etc/php5/fpm/pool.d/www.conf && \
sed -i 's/;listen\.allowed_clients.*/listen.allowed_clients = 127.0.0.1/g' \
  /etc/php5/fpm/pool.d/www.conf ) 2>&1 ) \
  || echo_failure
check_error_exit "${ERROR}"
echo_success

# Restart PHP-FPM
status_message "Restarting PHP-FPM"
ERROR=$(( service php5-fpm restart >/dev/null ) 2>&1 ) \
  || echo_failure
check_error_exit "${ERROR}"
echo_success

# Restart Nginx
status_message "Restarting Nginx"
ERROR=$(( service nginx restart >/dev/null ) 2>&1 ) \
  || echo_failure
check_error_exit "${ERROR}"
echo_success

# Get MySQL root password
echo "MySQL database for Kimai will now be setup.."
read -s -p "Enter MySQL password: " rootpass
echo

# Generate MySQL password
status_message "Generating MySQL user password"
userpass=$(( cat /dev/urandom | tr -dc 'a-zA-Z0-9' | \
          fold -w "${passlength}" | head -n 1 ) 2>/dev/null )
if [ -z "$userpass" ]; then echo_failure && exit 1; fi
echo_success

# Create MySQL user
status_message "Creating MySQL user"
ERROR=$( mysql -u root -p${rootpass} -e \
         "CREATE USER 'kimai'@'localhost' \
          IDENTIFIED BY '${userpass}';" 2>&1 ) \
  || echo_failure
check_error_exit "${ERROR}"
echo_success

# Set MySQL user privileges
status_message "Setting MySQL user privileges"
ERROR=$( mysql -u root -p${rootpass} -e \
         "GRANT CREATE,DROP,USAGE,SELECT,INSERT,UPDATE,DELETE \
          ON kimai.* TO 'kimai'@'localhost'; \
          FLUSH PRIVILEGES;" 2>&1 ) \
  || echo_failure
check_error_exit "${ERROR}"
echo_success

# Create MySQL database
status_message "Creating MySQL database"
ERROR=$( mysql -u root -p${rootpass} -e \
         'CREATE DATABASE kimai; USE kimai;' 2>&1 ) \
  || echo_failure
check_error_exit "${ERROR}"
echo_success

# Remove archive
status_message "Removing archive"
ERROR=$( rm "/tmp/kimai-v${kimaiversion}.tar.gz" 2>&1 ) \
  || echo_failure
check_error_exit "${ERROR}"
echo_success

# Last words
echo -e "\

The script has completed successfully! All software and files required for
Kimai should now be present and properly set up. To complete the installation
of Kimai use a browser to visit the IP address of this host and follow the
instructions of the Kimai installation wizard.

\e[4mImportant to remember:\e[0m
MySQL user: kimai
MySQL pass: ${userpass}
Database:   kimai
"