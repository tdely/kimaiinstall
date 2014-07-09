#!/bin/bash

# Defaults
CLEAN_ARCHIVE="no"
KIMAI_VERSION="0.9.3-rc.1"
WEB_DIR="/var/www"
DATABASE="kimai"
MYSQL_USER="kimai"
MYSQL_PASS_LENGTH=15
NGINX_RLIMIT=1024
NGINX_NPROC=$( nproc )

# Applications to install
APP_LIST=( curl nginx php5-fpm php-apc mysql-server php5-mysqlnd )

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
function echo_version {
    echo "\
kimaiinstall 1.1.0
License GPLv2: GNU GPL version 2 <http://gnu.org/licenses/gpl.html>.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.

Written by Tobias Logren Dély"
}
function echo_help {
echo "\
Usage: $0 [OPTIONS]... <DOMAIN NAME>
Install Kimai and necessary supporting software.

  -c, --clean              remove downloaded archive after extraction
  -d, --database name      name of MySQL database to create
  -f, --fd-limit N         allow N file descriptors between all Nginx workers
  -h, --help               display this help and exit
  -k, --kimai version      version of Kimai to install
  -n, --nworkers N         allow N worker processes to be used by Nginx
  -p, --passlength K       generate password K characters long for MySQL user
  -u, --user name          name of MySQL user to create for Kimai
  -v, --version            output version information and exit
  -w, --webdir path        root directory path for Nginx website files

Report kimaiinstall bugs to https://github.com/tdely/kimaiinstall/issues
For complete documentation, see: https://github.com/tdely/kimaiinstall"
}

# Parse arguments
while :
do
    case "$1" in
      -c | --clean )
          CLEAN_ARCHIVE="yes"
          shift ;;
      -d | --database )
          [[ $2 =~ ^[A-Za-z0-9_-]+$ ]] \
            || { echo "Error: -d, --database may only contain alphanumeric "\
                      "characters and '-', '_'"; exit 1; }
          DATABASE="$2"
          shift 2 ;;
      -f | --fd-limit )
          [[ $2 =~ ^[0-9]+$ ]] \
            || { echo "Error: -f, --fd-limit must be an integer"; exit 1; }
          NGINX_RLIMIT="$2"
          shift 2 ;;
      -h | --help )
          echo_help
          exit 0 ;;
      -k | --kimai)
          [[ $2 =~ ^[A-Za-z0-9.-_]+$ ]] \
            || { echo "Error: -k, --kimai may only contain alphanumeric "\
                      "characters and '.', '-', '_'"; exit 1; }
          KIMAI_VERSION="$2"
          shift 2 ;;
      -n | --nworkers)
          [[ $2 =~ ^[0-9]+$ ]] \
            || { echo "Error: -n, --nworkers must be an integer"; exit 1; }
          NGINX_NPROC="$2"
          shift 2 ;;
      -p | --passlength)
          [[ $2 =~ ^[0-9]+$ ]] \
            || { echo "Error: -p, --passlength must be an integer"; exit 1; }
          MYSQL_PASS_LENGTH="$2"
          shift 2 ;;
      -u | --user)
          [[ $2 =~ ^[a-z]+$ ]] \
            || { echo "Error: -u, --user may only contain lowercase letters";\
                 exit 1; }
          MYSQL_USER="$2"
          shift 2 ;;
      -v | --version)
          echo_version
          exit 0 ;;
      -w | --webdir)
          [[ $2 =~ ^/([A-Za-z0-9._-]|/)+$ ]] \
            || { echo "Error: -w, --webdir must be an absulute path and may"\
                      "only contain alphanumeric characters and '.', '-', '_'"
                 exit 1; }
          WEB_DIR="$2"
          shift 2 ;;
      --)
          shift
          break ;;
      -*)
          echo "Error: Unknown option: $1" >&2
          exit 1 ;;
      *)
          break ;;
    esac
done


# Must be run as root
if [ $EUID != 0 ]; then
    echo "Error: must be run as root"
    exit 1
fi

DOMAIN=$1
# Make sure domain name was given
if [ -z "${DOMAIN}" ]; then
    echo "Error: domain name not given"
    exit 1
fi
# Domain must be valid
if ! [[ ${DOMAIN} =~ ^([a-z0-9]+)([a-z0-9.-]+)([a-z0-9]+)$ ]]; then
    echo >&2 "Error: domain name must be lowercase and of valid format"
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
  || { echo -e >&2 "Error: apt-get \e[31mfailed\e[0m to update"; exit 1; }

# Install applications
echo "Installing required applications.."
for item in "${applist[@]}"
do
    apt-get install "${item}" -y \
      || { echo -e >&2 "apt-get \e[31mfailed\e[0m on ${item}"; exit 1; }
done

# Create /var/www
echo "Checking if ${WEB_DIR} exists.."
if [ ! -d "${WEB_DIR}" ]; then
    echo "Not found"
    status_message "Creating directory"
    error=$( mkdir "${WEB_DIR}" 2>&1 ) \
      || echo_failure
    check_error_exit "${error}"
    echo_success
else
    echo "Found"
fi

# Download Kimai
echo "Checking if Kimai is already downloaded.."
if [ ! -f "/tmp/kimai-v${KIMAI_VERSION}.tar.gz" ]; then
    echo "Not found"
    echo "Downloading Kimai ${KIMAI_VERSION}"
    curl "https://github.com/kimai/kimai/archive/v${KIMAI_VERSION}.tar.gz" \
      -\#Lo "/tmp/kimai-v${KIMAI_VERSION}.tar.gz" \
      || exit 1
else
    echo "Found"
fi

# Extract archive
status_message "Extracting archive"
error=$( tar -xzf "/tmp/kimai-v${KIMAI_VERSION}.tar.gz" -C "${WEB_DIR}" 2>&1 ) \
  || echo_failure
check_error_exit "${error}"
echo_success

# Construct the full path to Kimai
kimai_path="${WEB_DIR}/kimai-${KIMAI_VERSION}"

# Set ownership
status_message "Setting ownership of Kimai"
error=$( chown -R "www-data:www-data" \
           "${kimai_path}" 2>&1 ) \
  || echo_failure
check_error_exit "${error}"
echo_success

# Set permissions
status_message "Setting permissions on Kimai"
error=$( find "/var/www/kimai-${KIMAI_VERSION}" \
           -type d -exec chmod 0550 {} \; 2>&1 ) \
  || echo_failure
check_error_exit "${error}"
error=$( find "${kimai_path}" \
           -type f -exec chmod 0440 {} \; 2>&1 ) \
  || echo_failure
check_error_exit "${error}"
error=$( chmod 0770 "${kimai_path}/core/temporary" 2>&1 ) \
  || echo_failure
check_error_exit "${error}"
error=$( chmod 0660 "${kimai_path}/core/temporary/logfile.txt" 2>&1 ) \
  || echo_failure
check_error_exit "${error}"
error=$( chmod 0770 "${kimai_path}/core/includes" 2>&1 ) \
  || echo_failure
check_error_exit "${error}"
echo_success


let NGINX_WCONN=${NGINX_RLIMIT}/${NGINX_NPROC}

# Configure Nginx
status_message "Writing configuration to /etc/nginx.conf"
error=$(( echo "\
user                        www-data;
worker_processes            ${NGINX_NPROC};
worker_priority             15;
worker_rlimit_nofile        ${NGINX_RLIMIT};
pid                         /var/run/nginx.pid;

events {
  worker_connections        ${NGINX_WCONN};
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
check_error_exit "${error}"
echo_success

# Setup Kimai site
status_message "Writing site configuration to /etc/nginx/sites-available/kimai"
error=$(( echo -e "\
server {
  root        /var/www/kimai-${KIMAI_VERSION}/core;
  index       index.html index.htm index.php;

  server_name ${DOMAIN}
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
check_error_exit "${error}"
echo_success

# Disable default site
status_message "Disabling default site"
error=$( if [ -x "/etc/nginx/sites-enabled/default" ]; then \
             rm "/etc/nginx/sites-enabled/default" 2>&1; fi ) \
  || echo_failure
check_error_exit "${error}"
echo_success

# Enable Kimai site
status_message "Enabling Kimai site"
error=$(( rm "/etc/nginx/sites-enabled/kimai" >/dev/null 2>&1 ) \
  ; ln -s "/etc/nginx/sites-available/kimai" \
          "/etc/nginx/sites-enabled/kimai" 2>&1 ) \
  || echo_failure
check_error_exit "${error}"
echo_success

# Configure PHP-FPM
status_message "Configuring PHP-FPM"
error=$(( sed -i 's/;listen = .*/listen = \/var\/run\/php5-fpm.sock/g' \
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
check_error_exit "${error}"
echo_success

# Restart PHP-FPM
status_message "Restarting PHP-FPM"
error=$(( service php5-fpm restart >/dev/null ) 2>&1 ) \
  || echo_failure
check_error_exit "${error}"
echo_success

# Restart Nginx
status_message "Restarting Nginx"
error=$(( service nginx restart >/dev/null ) 2>&1 ) \
  || echo_failure
check_error_exit "${error}"
echo_success

# Get MySQL root password
echo "MySQL database for Kimai will now be setup.."
read -s -p "Enter MySQL password: " root_pass
echo

# Generate MySQL password
status_message "Generating MySQL user password"
user_pass=$(( cat /dev/urandom | tr -dc 'a-zA-Z0-9' | \
          fold -w "${MYSQL_PASS_LENGTH}" | head -n 1 ) 2>/dev/null )
if [ -z "${user_pass}" ]; then echo_failure && exit 1; fi
echo_success

# Create MySQL user
status_message "Creating MySQL user"
error=$( mysql -u root -p${root_pass} -e \
         "CREATE USER '${MYSQL_USER}'@'localhost' \
          IDENTIFIED BY '${user_pass}';" 2>&1 ) \
  || echo_failure
check_error_exit "${error}"
echo_success

# Set MySQL user privileges
status_message "Setting MySQL user privileges"
error=$( mysql -u root -p${root_pass} -e \
         "GRANT CREATE,DROP,USAGE,SELECT,INSERT,UPDATE,DELETE \
          ON ${DATABASE}.* TO '${MYSQL_USER}'@'localhost'; \
          FLUSH PRIVILEGES;" 2>&1 ) \
  || echo_failure
check_error_exit "${error}"
echo_success

# Create MySQL database
status_message "Creating MySQL database"
error=$( mysql -u root -p${root_pass} -e \
         "CREATE DATABASE ${DATABASE}; USE ${DATABASE};" 2>&1 ) \
  || echo_failure
check_error_exit "${error}"
echo_success

# Remove archive
if [ ${CLEAN_ARCHIVE} == "yes" ]; then
  status_message "Removing archive"
  error=$( rm "/tmp/kimai-v${KIMAI_VERSION}.tar.gz" 2>&1 ) \
    || echo_failure
  check_error_exit "${error}"
  echo_success
fi

# Last words
echo -e "
The script has completed successfully! All software and files required for
Kimai should now be present and properly set up. To complete the installation
of Kimai use a browser to visit the IP address of this host and follow the
instructions of the Kimai installation wizard.

\e[4mImportant to remember:\e[0m
MySQL user: ${MYSQL_USER}
MySQL pass: ${user_pass}
Database:   ${DATABASE}
"
