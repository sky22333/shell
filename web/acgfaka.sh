#!/bin/bash
# 一键部署异次元发卡脚本

# 检查是否已经安装 acgfaka
if [ -d "/var/www/html/acgfaka" ]; then
    echo -e "\033[32m检测到 acgfaka 已经安装。\033[0m"
    echo -e "\033[33m如需重新安装，请删除站点文件：/var/www/html/acgfaka 并做好相关备份。\033[0m"
    exit 0
fi

while true; do
    echo -e "\033[33m请输入您的域名(确保已经解析到本机): \033[0m"
    read DOMAIN
    
    echo -e "\033[32m您输入的域名是: $DOMAIN\033[0m"
    echo -e "\033[33m请确认这个域名是否正确 (yes/no): \033[0m"
    read CONFIRM
    
    if [[ "${CONFIRM,,}" == "yes" || "${CONFIRM,,}" == "y" ]]; then
        echo -e "\033[32m域名确认成功: $DOMAIN\033[0m"
        break
    else
        echo -e "\033[31m请重新输入域名。\033[0m"
    fi
done

# 安装必要的软件包
echo -e "\033[32m安装必要的软件包...首次安装可能较慢...请耐心等待。。。\033[0m"
sudo apt-get update -q
sudo apt-get install -y -q mariadb-server php php-mysql php-fpm php-curl php-json php-cgi php-mbstring php-xml php-gd php-xmlrpc php-soap php-intl php-opcache php-zip wget unzip apache2 socat curl

PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
PHP_INI_FILE="/etc/php/${PHP_VERSION}/fpm/php.ini"
OPCACHE_FILE_CACHE_DIR="/var/cache/opcache"

# 确保缓存目录存在并设置权限
if [ ! -d "$OPCACHE_FILE_CACHE_DIR" ]; then
    echo -e "\033[32m创建 OPcache 缓存目录...\033[0m"
    sudo mkdir -p "$OPCACHE_FILE_CACHE_DIR"
    sudo chown -R www-data:www-data "$OPCACHE_FILE_CACHE_DIR"
fi

# 确保 OPcache 配置存在
if ! grep -q "^opcache.enable=1" "$PHP_INI_FILE"; then
    echo -e "\033[32m启用 OPcache 扩展...请稍等...\033[0m"
    
    # 写入 OPcache 配置
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
opcache.file_cache_only=0  # 修改为 0 表示启用内存缓存
opcache.file_cache_consistency_checks=1
EOL

    echo -e "\033[32mOPcache 配置已完成。\033[0m"
fi

# 重启 PHP-FPM 服务
sudo systemctl restart php${PHP_VERSION}-fpm

# 启动并启用 Apache 服务
sudo systemctl start apache2
sudo systemctl enable apache2

sudo systemctl start mariadb
sudo systemctl enable mariadb

sudo mysql_secure_installation <<EOF

y
y
y
y
y
EOF

# 创建acgfaka数据库和用户
DB_NAME="acgfaka"
DB_USER="acguser"
DB_PASSWORD=$(openssl rand -base64 12)

sudo mysql -u root -e "DROP USER IF EXISTS '${DB_USER}'@'localhost';"
sudo mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
sudo mysql -u root -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';"
sudo mysql -u root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
sudo mysql -u root -e "FLUSH PRIVILEGES;"

# 下载并配置acgfaka
mkdir -p /var/www/html
cd /var/www/html
wget https://github.com/lizhipay/acg-faka/archive/refs/heads/main.zip
unzip main.zip > /dev/null 2>&1
rm main.zip
mv acg-faka-main acgfaka

sudo chown -R www-data:www-data /var/www/html/acgfaka
sudo find /var/www/html/acgfaka/ -type d -exec chmod 750 {} \;
sudo find /var/www/html/acgfaka/ -type f -exec chmod 640 {} \;

# 配置 Apache 虚拟主机
APACHE_CONF="/etc/apache2/sites-available/acgfaka.conf"
sudo tee $APACHE_CONF > /dev/null <<EOL
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot /var/www/html/acgfaka

    <Directory /var/www/html/acgfaka>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOL

sudo systemctl stop apache2

generate_random_email() {
    local prefix=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 10)
    echo "${prefix}@gmail.com"
}

# SSL证书生成和配置
generate_ssl_certificate() {
    echo -e "\033[0;32m正在为 $DOMAIN 生成 SSL 证书...\033[0m"
    
    # 确保 acme.sh 已安装
    if ! command -v acme.sh &> /dev/null; then
        echo -e "\033[0;32macme.sh 未安装，正在安装...\033[0m"
        curl https://get.acme.sh | sh
        source ~/.bashrc
    else
        echo -e "\033[0;32macme.sh 已安装\033[0m"
    fi
    
    local email=$(generate_random_email)
    echo -e "\033[0;32m使用随机生成的邮箱地址 $email 进行账户注册...\033[0m"

    # 注册账户并设置电子邮件地址
    ~/.acme.sh/acme.sh --register-account -m "$email"
    
    ~/.acme.sh/acme.sh --issue --force --standalone -d "$DOMAIN"
    
    if [ $? -ne 0 ]; then
        echo -e "\033[0;31mSSL 证书生成失败\033[0m"
        exit 1
    fi

    local cert_path="/root/.acme.sh/${DOMAIN}_ecc/fullchain.cer"
    local key_path="/root/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.key"

    ~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
        --key-file "$key_path" \
        --fullchain-file "$cert_path"

    # 配置 Apache 使用 SSL 证书
    APACHE_SSL_CONF="/etc/apache2/sites-available/acgfaka-ssl.conf"
    sudo tee $APACHE_SSL_CONF > /dev/null <<EOL
<VirtualHost *:443>
    ServerName $DOMAIN
    DocumentRoot /var/www/html/acgfaka

    <Directory /var/www/html/acgfaka>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined

    SSLEngine on
    SSLCertificateFile $cert_path
    SSLCertificateKeyFile $key_path
</VirtualHost>
EOL

    # 启用 Apache 的 mod_rewrite 模块
    sudo a2enmod rewrite

    # 启用 SSL 模块
    sudo a2enmod ssl

    # 启用 HTTP 站点配置
    sudo a2ensite acgfaka.conf

    # 启用 HTTPS 站点配置
    sudo a2ensite acgfaka-ssl.conf

    # 重启 Apache 配置
    sudo systemctl restart apache2

    echo -e "\033[0;32m证书路径: $cert_path\033[0m"
    echo -e "\033[0;32m密钥路径: $key_path\033[0m"
}

generate_ssl_certificate

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