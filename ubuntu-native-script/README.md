Here's the Ubuntu-equivalent deployment guide, following the same structure as your README:

## Deploy Pre-Requisites

Ubuntu uses `ufw` instead of `firewalld` (though you can install `firewalld` on Ubuntu too — I'll show `ufw` since it's native, and note the `firewalld` alternative).

**Option A: UFW (recommended, native to Ubuntu)**
```bash
sudo apt update
sudo apt install -y ufw
sudo ufw enable
sudo ufw status
```

**Option B: FirewallD (if you want to keep it identical to the CentOS guide)**
```bash
sudo apt update
sudo apt install -y firewalld
sudo systemctl start firewalld
sudo systemctl enable firewalld
sudo systemctl status firewalld
```
I'll use `firewalld` commands below so the rest of the guide maps 1:1 to your original — swap in `ufw allow <port>/tcp` if you go with Option A.

## Deploy and Configure Database

1. Install MariaDB

```bash
sudo apt update
sudo apt install -y mariadb-server
sudo vi /etc/mysql/mariadb.conf.d/50-server.cnf
sudo systemctl start mariadb
sudo systemctl enable mariadb
```

2. Configure firewall for Database

```bash
sudo firewall-cmd --permanent --zone=public --add-port=3306/tcp
sudo firewall-cmd --reload
```
(UFW equivalent: `sudo ufw allow 3306/tcp`)

3. Configure Database

```bash
sudo mysql
```
```sql
MariaDB > CREATE DATABASE ecomdb;
MariaDB > CREATE USER 'ecomuser'@'localhost' IDENTIFIED BY 'ecompassword';
MariaDB > GRANT ALL PRIVILEGES ON *.* TO 'ecomuser'@'localhost';
MariaDB > FLUSH PRIVILEGES;
```

> On a multi-node setup, remember to provide the IP address of the web server here: `'ecomuser'@'web-server-ip'`

4. Load Product Inventory Information to database

```bash
cat > db-load-script.sql <<-EOF
USE ecomdb;
CREATE TABLE products (id mediumint(8) unsigned NOT NULL auto_increment,Name varchar(255) default NULL,Price varchar(255) default NULL, ImageUrl varchar(255) default NULL,PRIMARY KEY (id)) AUTO_INCREMENT=1;

INSERT INTO products (Name,Price,ImageUrl) VALUES ("Laptop","100","c-1.png"),("Drone","200","c-2.png"),("VR","300","c-3.png"),("Tablet","50","c-5.png"),("Watch","90","c-6.png"),("Phone Covers","20","c-7.png"),("Phone","80","c-8.png"),("Laptop","150","c-4.png");
EOF
```

Run the SQL script:
```bash
sudo mysql < db-load-script.sql
```

## Deploy and Configure Web

1. Install required packages

Ubuntu uses `apache2` instead of `httpd`, and the PHP MySQL driver package is `php-mysql`:

```bash
sudo apt update
sudo apt install -y apache2 php libapache2-mod-php php-mysql
sudo firewall-cmd --permanent --zone=public --add-port=80/tcp
sudo firewall-cmd --reload
```
(UFW equivalent: `sudo ufw allow 80/tcp` or `sudo ufw allow 'Apache'`)

2. Configure Apache

Ubuntu's Apache config uses `DirectoryIndex` inside `/etc/apache2/mods-enabled/dir.conf`, not `/etc/httpd/conf/httpd.conf`:

```bash
sudo sed -i 's/index.html/index.php/g' /etc/apache2/mods-enabled/dir.conf
```

You'll also want `index.php` to load first — the default order in that file is usually `index.html index.cgi index.pl index.php ...`, so moving/replacing `index.html` with `index.php` (or just putting `index.php` first) does the trick. Then enable PHP and rewrite modules if needed:

```bash
sudo a2enmod php* 2>/dev/null || true
sudo a2enmod rewrite
```

3. Start Apache

```bash
sudo systemctl start apache2
sudo systemctl enable apache2
```

4. Download code

```bash
sudo apt install -y git
sudo git clone https://github.com/kodekloudhub/learning-app-ecommerce.git /var/www/html/
```

> Note: on Ubuntu, Apache's default document root already contains an `index.html`. You may need to remove it first so it doesn't conflict:
> ```bash
> sudo rm -f /var/www/html/index.html
> ```
> (Run this *before* the `git clone`, or clone to a temp dir and move contents into `/var/www/html/` if the directory isn't empty.)

5. Create and Configure the `.env` File

```bash
cat > /var/www/html/.env <<-EOF
DB_HOST=localhost
DB_USER=ecomuser
DB_PASSWORD=ecompassword
DB_NAME=ecomdb
EOF
```

6. Update `index.php`

Same PHP code as your original — no changes needed here, this part is OS-agnostic:

```php
<?php
// Function to load environment variables from a .env file
function loadEnv($path)
{
    if (!file_exists($path)) {
        return false;
    }

    $lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    foreach ($lines as $line) {
        if (strpos(trim($line), '#') === 0) {
            continue;
        }

        list($name, $value) = explode('=', $line, 2);
        $name = trim($name);
        $value = trim($value);
        putenv(sprintf('%s=%s', $name, $value));
    }
    return true;
}

// Load environment variables from .env file
loadEnv(__DIR__ . '/.env');

// Retrieve the database connection details from environment variables
$dbHost = getenv('DB_HOST');
$dbUser = getenv('DB_USER');
$dbPassword = getenv('DB_PASSWORD');
$dbName = getenv('DB_NAME');
?>
```

> On a multi-node setup, remember to provide the IP address of the database server in the `.env` file.

7. Fix file ownership/permissions (good practice on Ubuntu, since `git clone` as root/sudo leaves files owned by root)

```bash
sudo chown -R www-data:www-data /var/www/html/
sudo systemctl restart apache2
```

8. Test

```bash
curl http://localhost
```

### Key differences summary
| CentOS | Ubuntu |
|---|---|
| `yum` | `apt` |
| `httpd` | `apache2` |
| `php-mysqlnd` | `php-mysql` (plus `libapache2-mod-php`) |
| `/etc/httpd/conf/httpd.conf` | `/etc/apache2/mods-enabled/dir.conf` |
| `firewalld` (common on CentOS) | `ufw` (native to Ubuntu, though `firewalld` can be installed) |
| Apache runs as `apache` user | Apache runs as `www-data` user |
