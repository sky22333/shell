#!/bin/bash
# 一键部署WordPress脚本
# 项目地址https://github.com/sky22333/shell

# 检查是否已经安装 WordPress
if [ -d "/var/www/html/wordpress" ]; then
    echo -e "\033[32m检测到 WordPress 已经安装。\033[0m"
    echo -e "\033[33m如需重新安装，请删除站点文件：/var/www/html/wordpress 并做好相关备份。\033[0m"
    exit 0
fi

while true; do
    echo -e "\033[33m请输入您的域名(确保已经解析到本机): \033[0m"
    read DOMAIN
    
    echo -e "\033[32m您输入的域名是: $DOMAIN\033[0m"
    echo -e "\033[33m为防止输错，请核对域名是否正确 (yes/no？直接回车代表正确): \033[0m"
    read CONFIRM
    
    # 如果用户按回车，则默认为确认
    if [[ -z "${CONFIRM// }" ]]; then
        CONFIRM="yes"
    fi
    
    if [[ "${CONFIRM,,}" == "yes" || "${CONFIRM,,}" == "y" ]]; then
        echo -e "\033[32m域名确认成功: $DOMAIN\033[0m"
        break
    else
        echo -e "\033[31m请重新输入域名。\033[0m"
    fi
done

echo -e "\033[32m更新系统包...首次更新可能较慢...请耐心等待。。。\033[0m"
sudo apt-get update -yq

echo -e "\033[32m安装必要的软件包...首次安装可能较慢...请耐心等待。。。\033[0m"
sudo apt-get install -y -q mariadb-server php php-mysql php-fpm php-curl php-json php-cgi php-mbstring php-xml php-gd php-xmlrpc php-soap php-intl php-opcache php-zip wget unzip

sudo systemctl start mariadb
sudo systemctl enable mariadb

sudo mysql_secure_installation <<EOF

y
y
y
y
y
EOF

# 项目地址https://github.com/sky22333/shell
# 创建WordPress数据库和用户
DB_NAME="wordpress"
DB_USER="wpuser"
DB_PASSWORD=$(openssl rand -base64 12)

sudo mysql -u root -e "DROP USER IF EXISTS '${DB_USER}'@'localhost';"
sudo mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mysql -u root -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
sudo mysql -u root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
sudo mysql -u root -e "FLUSH PRIVILEGES;"

# 下载并配置WordPress
mkdir -p /var/www/html
cd /var/www/html
wget https://zh-cn.wordpress.org/latest-zh_CN.tar.gz
tar -xzvf latest-zh_CN.tar.gz > /dev/null 2>&1
rm latest-zh_CN.tar.gz

sudo chown -R www-data:www-data /var/www/html/wordpress
sudo find /var/www/html/wordpress/ -type d -exec chmod 750 {} \;
sudo find /var/www/html/wordpress/ -type f -exec chmod 640 {} \;

if [ ! -d /etc/apt/sources.list.d/ ]; then
    sudo mkdir -p /etc/apt/sources.list.d/
fi
sudo apt install -y -q debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update -yq
sudo apt install -y -q caddy

PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')

OPCACHE_FILE_CACHE_DIR="/var/www/html/wordpress/wp-content/opcache"
sudo mkdir -p $OPCACHE_FILE_CACHE_DIR
sudo chown www-data:www-data $OPCACHE_FILE_CACHE_DIR

# 配置OPcache
sudo bash -c "cat > /etc/php/${PHP_VERSION}/fpm/conf.d/10-opcache.ini" <<EOF
[opcache]
opcache.enable=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=9000
opcache.revalidate_freq=5
opcache.save_comments=1
opcache.file_cache=${OPCACHE_FILE_CACHE_DIR}
opcache.file_cache_size=128
opcache.file_cache_only=0
opcache.file_cache_consistency_checks=1
EOF

# 重启PHP-FPM服务
sudo systemctl restart php${PHP_VERSION}-fpm

if systemctl is-active --quiet apache2; then
    sudo systemctl stop apache2
    sudo systemctl disable apache2
    sudo apt remove --purge apache2 -y
else
    echo -e "当前环境是正常状态。"
fi

sudo bash -c "cat > /etc/caddy/Caddyfile" <<EOF
$DOMAIN {
    root * /var/www/html/wordpress
    encode zstd gzip
    php_fastcgi unix//run/php/php${PHP_VERSION}-fpm.sock
    file_server
}
EOF

sudo systemctl restart caddy

echo -e "\033[32m============================================================\033[0m"
echo -e "\033[32m                  数据库信息: \033[0m"
echo -e "\033[32m============================================================\033[0m"
echo -e "\033[33m数据库名:     \033[36m${DB_NAME}\033[0m"
echo -e "\033[33m用户名:       \033[36m${DB_USER}\033[0m"
echo -e "\033[33m密码:         \033[36m${DB_PASSWORD}\033[0m"
echo -e "\033[32m============================================================\033[0m"
echo -e "\033[32m站点域名:     \033[36m${DOMAIN}\033[0m"
echo -e "\033[32m网站后台:     \033[36m${DOMAIN}/wp-admin\033[0m"
echo -e "\033[32m您的 WordPress 站点已经部署完成，请记录好相关信息。\033[0m"
echo -e "\033[32m============================================================\033[0m"
