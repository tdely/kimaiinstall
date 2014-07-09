kimaiinstall
============
Debian-based automated installation of the Kimai time-tracking application, using Nginx and MySQL.
The script has been tested with and is set to install Kimai version 0.9.3-rc.1 by default.

Changing the version of Kimai to install may be done by specifying the version with the argument `-k` or `--kimai`, be advised however that other versions have not been tested and may not be compatible with this script.

Usage
--------------
Call the script with your prefered domain as a parameter: `bash kimaiinstall <domain>`

`Usage: kimaiinstall.sh [OPTIONS]... <DOMAIN NAME>
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
  -w, --webdir path        root directory path for Nginx website files`

After the script has successfully finished, browse to the Kimai application and proceed with the installation through the Kimai installation wizard.

Installation process
--------------
The script will perform the following main tasks:

1. Install APT packages: `curl nginx php5-fpm php-apc mysql-server php5-mysqlnd`
2. Fetch and extract Kimai archive
3. Set ownership and permissions
4. Configure Nginx and PHP-FPM
5. Create MySQL user and database for Kimai

You will be prompted for a root password during the MySQL installation, you must repeat the root password prior to MySQL user and database creation.
