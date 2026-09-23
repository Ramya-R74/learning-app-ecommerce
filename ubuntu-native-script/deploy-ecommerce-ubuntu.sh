#!/bin/bash
#
# Automate ECommerce Application Deployment (Ubuntu version)
# Adapted from the CentOS deployment script for learning purposes.
#
# What this script does, in order:
#   1. Sets up the database server (MariaDB)
#   2. Sets up the web server (Apache + PHP)
#   3. Deploys the application code
#   4. Runs a quick test to confirm the site is serving data
#
# Usage:
#   chmod +x deploy-ecommerce-ubuntu.sh
#   sudo ./deploy-ecommerce-ubuntu.sh
#

# Exit immediately if any command fails, and treat unset variables as errors.
# This is a shell scripting best practice - it stops the script early
# instead of continuing after something has gone wrong.
set -euo pipefail

# --- Configuration (change these if you need different values) -----------
DB_NAME="ecomdb"
DB_USER="ecomuser"
DB_PASSWORD="ecompassword"
APP_DIR="/var/www/html"
REPO_URL="https://github.com/kodekloudhub/learning-app-ecommerce.git"


###########################################################################
# Function: print_color
# Prints a message in a given color, so script output is easy to read.
# Arguments:
#   $1 - color name: "green" or "red"
#   $2 - message to print
###########################################################################
function print_color() {
  local NC='\033[0m' # No Color
  local COLOR

  case "$1" in
    "green") COLOR='\033[0;32m' ;;
    "red")   COLOR='\033[0;31m' ;;
    *)       COLOR='\033[0m' ;;
  esac

  echo -e "${COLOR}$2${NC}"
}


###########################################################################
# Function: check_service_status
# Confirms a systemd service is active. Exits the script if it is not.
# Arguments:
#   $1 - service name, e.g. "apache2", "mariadb"
###########################################################################
function check_service_status() {
  local service_is_active
  service_is_active=$(sudo systemctl is-active "$1" || true)

  if [ "$service_is_active" = "active" ]; then
    print_color "green" "$1 is active and running"
  else
    print_color "red" "$1 is not active/running"
    exit 1
  fi
}


###########################################################################
# Function: is_ufw_rule_configured
# Confirms a given port is allowed through UFW. Exits the script if not.
# Arguments:
#   $1 - port number, e.g. 3306, 80
###########################################################################
function is_ufw_rule_configured() {
  local ufw_status
  ufw_status=$(sudo ufw status | grep "$1" || true)

  if [[ -n "$ufw_status" ]]; then
    print_color "green" "UFW has port $1 configured"
  else
    print_color "red" "UFW port $1 is not configured"
    exit 1
  fi
}


###########################################################################
# Function: check_item
# Checks whether a given piece of text is present in some output.
# Arguments:
#   $1 - the output/text to search in
#   $2 - the item to search for
###########################################################################
function check_item() {
  if [[ "$1" == *"$2"* ]]; then
    print_color "green" "Item $2 is present on the web page"
  else
    print_color "red" "Item $2 is not present on the web page"
  fi
}


# ==========================================================================
print_color "green" "---------------- Setup Database Server ------------------"
# ==========================================================================

# Update package lists so we install the latest available versions.
print_color "green" "Updating package lists.."
sudo apt update

# Install and configure UFW (Ubuntu's native firewall tool).
print_color "green" "Installing UFW.."
sudo apt install -y ufw
sudo ufw --force enable

# Install and start MariaDB.
print_color "green" "Installing MariaDB Server.."
sudo apt install -y mariadb-server

print_color "green" "Starting MariaDB Server.."
sudo systemctl start mariadb
sudo systemctl enable mariadb

check_service_status mariadb

# Open the database port through the firewall.
print_color "green" "Configuring UFW rule for database.."
sudo ufw allow 3306/tcp

is_ufw_rule_configured 3306

# Create the database and application user.
print_color "green" "Setting up database.."
cat > setup-db.sql <<-EOF
  CREATE DATABASE IF NOT EXISTS ${DB_NAME};
  CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
  GRANT ALL PRIVILEGES ON *.* TO '${DB_USER}'@'localhost';
  FLUSH PRIVILEGES;
EOF

sudo mysql < setup-db.sql

# Load the product inventory into the database.
print_color "green" "Loading inventory data into database.."
cat > db-load-script.sql <<-EOF
USE ${DB_NAME};
CREATE TABLE IF NOT EXISTS products (
  id mediumint(8) unsigned NOT NULL auto_increment,
  Name varchar(255) default NULL,
  Price varchar(255) default NULL,
  ImageUrl varchar(255) default NULL,
  PRIMARY KEY (id)
) AUTO_INCREMENT=1;

INSERT INTO products (Name,Price,ImageUrl) VALUES
  ("Laptop","100","c-1.png"),
  ("Drone","200","c-2.png"),
  ("VR","300","c-3.png"),
  ("Tablet","50","c-5.png"),
  ("Watch","90","c-6.png"),
  ("Phone Covers","20","c-7.png"),
  ("Phone","80","c-8.png"),
  ("Laptop","150","c-4.png");
EOF

sudo mysql < db-load-script.sql

# Verify the data actually loaded.
mysql_db_results=$(sudo mysql -e "USE ${DB_NAME}; SELECT * FROM products;")

if [[ "$mysql_db_results" == *Laptop* ]]; then
  print_color "green" "Inventory data loaded into MariaDB"
else
  print_color "red" "Inventory data not loaded into MariaDB"
  exit 1
fi

print_color "green" "---------------- Setup Database Server - Finished ------------------"


# ==========================================================================
print_color "green" "---------------- Setup Web Server ------------------"
# ==========================================================================

# Install web server packages: Apache, PHP, and the PHP-MySQL connector.
print_color "green" "Installing Web Server Packages.."
sudo apt install -y apache2 php libapache2-mod-php php-mysql

# Open the web port through the firewall.
print_color "green" "Configuring UFW rule for web server.."
sudo ufw allow 80/tcp

is_ufw_rule_configured 80

# Make index.php the default page Apache looks for.
print_color "green" "Configuring Apache to prefer index.php.."
sudo sed -i 's/index.html/index.php/g' /etc/apache2/mods-enabled/dir.conf

# Start Apache.
print_color "green" "Starting Apache service.."
sudo systemctl start apache2
sudo systemctl enable apache2

check_service_status apache2

# Install git and download the application code.
print_color "green" "Installing GIT.."
sudo apt install -y git

# Apache ships a default index.html in /var/www/html - remove it so it
# doesn't take precedence over, or conflict with, the cloned app.
if [ -f "${APP_DIR}/index.html" ]; then
  sudo rm -f "${APP_DIR}/index.html"
fi

print_color "green" "Cloning application code.."
sudo git clone "$REPO_URL" "$APP_DIR"

# Create the .env file with database connection details.
print_color "green" "Creating .env file.."
sudo tee "${APP_DIR}/.env" > /dev/null <<-EOF
DB_HOST=localhost
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=${DB_NAME}
EOF

# Apache runs as the www-data user on Ubuntu, so the app files should
# be owned by www-data (git clone via sudo leaves them owned by root).
print_color "green" "Fixing file ownership.."
sudo chown -R www-data:www-data "$APP_DIR"

# Restart Apache to make sure everything is picked up cleanly.
sudo systemctl restart apache2

print_color "green" "---------------- Setup Web Server - Finished ------------------"


# ==========================================================================
print_color "green" "---------------- Testing Website ------------------"
# ==========================================================================

web_page=$(curl -s http://localhost)

for item in Laptop Drone VR Watch Phone; do
  check_item "$web_page" "$item"
done

print_color "green" "---------------- Deployment Complete ------------------"