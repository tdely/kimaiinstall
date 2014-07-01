kimaiinstall
============
Automated installation of the Kimai time-tracking application, using Nginx and MySQL.
The script has been tested and is set to install Kimai version 0.9.3-rc.1.

Changing the Kimai version to install may be done by changing the `kimaiversion` parameter, be advised however that other Kimai versions have not been tested and may not be compatible with this script.

Usage
--------------
Call the script with your prefered domain as a parameter: `bash kimaiinstall <domain>`.

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
