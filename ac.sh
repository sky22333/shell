#!/bin/bash
# 一键部署异次元发卡脚本

# 检查是否已经安装 acgfaka
if [ -d "/var/www/html/acgfaka" ]; then
    echo -e "\033[32m检测到 acgfaka 已经安装。\033[0m"
    echo -e "\033[33m如需重新安装，请删除站点文件：/var/www/html/acgfaka 并做好相关备份。\033[0m"
    exit 0
fi

# 获取用户输入的域名
while true; do
    echo -e "\033[33m请输入您的域名(确保已经解析到本机): \033[0m"
    read DOMAIN
    
    echo -e "\033[32m您输入的域名是: $DOMAIN\033[0m"
    echo -e "\033[33m请确认这个域名是否正确 (yes/no, 默认回车确认): \033[0m"
    read CONFIRM
    
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

# 安装必要的软件包
echo -e "\033[32m安装必要的软件包...首次安装可能较慢...请耐心等待。。。\033[0m"
sudo apt update -q
sudo apt install -y -q mariadb-server php8.1 php8.1-mysql php8.1-fpm php8.1-curl php8.1-cgi php8.1-mbstring php8.1-xml php8.1-gd php8.1-xmlrpc php8.1-soap php8.1-intl php8.1-opcache php8.1-zip wget unzip socat curl debian-keyring debian-archive-keyring apt-transport-https software-properties-common caddy

# 安装 Caddy
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list

# 更新源列表
sudo apt update -q

PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
PHP_INI_FILE="/etc/php/${PHP_VERSION}/fpm/php.ini"
OPCACHE_FILE_CACHE_DIR="/var/cache/opcache"

# 确保 OPcache 配置存在
if ! grep -q "^opcache.enable=1" "$PHP_INI_FILE"; then
    echo -e "\033[32m启用 OPcache 扩展...请稍等...\033[0m"
    
    sudo mkdir -p "$OPCACHE_FILE_CACHE_DIR"
    sudo chown -R www-data:www-data "$OPCACHE_FILE_CACHE_DIR"

    sudo tee -a "$PHP_INI_FILE" > /dev/null <<EOL
[opcache]
opcache.enable=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000
opcache.revalidate_freq=2
opcache.save_comments=1
opcache.file_cache=${OPCACHE_FILE_CACHE_DIR}
opcache.file_cache_size=128
opcache.file_cache_only=0  # 内存缓存启用
opcache.file_cache_consistency_checks=1
EOL
    echo -e "\033[32mOPcache 配置已完成。\033[0m"
fi

# 重启 PHP-FPM 服务
sudo systemctl restart php${PHP_VERSION}-fpm

# 启动并启用 Caddy 和 MariaDB 服务
sudo systemctl enable --now caddy mariadb

# 配置 MariaDB
sudo mysql_secure_installation <<EOF

y
y
y
y
y
EOF

# 创建数据库和用户
DB_NAME="acgfaka"
DB_USER="acguser"
DB_PASSWORD=$(openssl rand -base64 12)

sudo mysql -u root <<EOF
DROP USER IF EXISTS '${DB_USER}'@'localhost';
CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

# 下载并配置 acgfaka
sudo mkdir -p /var/www/html
cd /var/www/html
sudo wget https://github.com/lizhipay/acg-faka/archive/refs/heads/main.zip
sudo unzip main.zip > /dev/null 2>&1
sudo rm main.zip
sudo mv acg-faka-main acgfaka

sudo chown -R www-data:www-data /var/www/html/acgfaka
sudo find /var/www/html/acgfaka/ -type d -exec chmod 750 {} \;
sudo find /var/www/html/acgfaka/ -type f -exec chmod 640 {} \;

# 配置 Caddyfile
sudo tee /etc/caddy/Caddyfile > /dev/null <<EOL
$DOMAIN {
    root * /var/www/html/acgfaka
    encode zstd gzip
    file_server

    # PHP 处理
    php_fastcgi unix//run/php/php${PHP_VERSION}-fpm.sock
    
    # 伪静态
    try_files {path} {path}/ /index.php?s={path}&{query}
}
EOL

# 重新加载 Caddy 配置
sudo systemctl reload caddy

# 输出数据库信息
echo -e "\033[32m============================================================\033[0m"
echo -e "\033[32m                  数据库信息: \033[0m"
echo -e "\033[32m============================================================\033[0m"
echo -e "\033[33m数据库名:     \033[36m${DB_NAME}\033[0m"
echo -e "\033[33m数据库账号:   \033[36m${DB_USER}\033[0m"
echo -e "\033[33m数据库密码:   \033[36m${DB_PASSWORD}\033[0m"
echo -e "\033[32m============================================================\033[0m"
echo -e "\033[32m站点域名:     \033[36m${DOMAIN}\033[0m"
echo -e "\033[32m站点已经部署完成，请记录好相关信息。\033[0m"
echo -e "\033[32m============================================================\033[0m"
