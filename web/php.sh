#!/bin/bash

# 检查操作系统并设置 PHP 仓库
if grep -Eqi "debian" /etc/issue || grep -Eqi "debian" /proc/version; then
    OS="debian"
    # Debian 系统设置 PHP 仓库
    curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
    echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" >/etc/apt/sources.list.d/php.list
elif grep -Eqi "ubuntu" /etc/issue || grep -Eqi "ubuntu" /proc/version; then
    OS="ubuntu"
    # Ubuntu 系统设置 PHP PPA
    sudo apt update -q
    sudo apt install -yq software-properties-common
    sudo add-apt-repository -y ppa:ondrej/php
else
    echo "不支持的操作系统。本脚本仅支持 Debian 或 Ubuntu。"
    exit 1
fi

# 更新源列表并安装必要的软件包
sudo apt update -q
sudo apt install -yq mariadb-server php8.1 php8.1-mysql php8.1-fpm php8.1-curl php8.1-cgi php8.1-mbstring \
    php8.1-xml php8.1-gd php8.1-xmlrpc php8.1-soap php8.1-intl php8.1-opcache php8.1-zip wget unzip socat curl caddy

# 获取 PHP 版本信息
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
PHP_INI_FILE="/etc/php/${PHP_VERSION}/fpm/php.ini"
OPCACHE_FILE_CACHE_DIR="/var/cache/opcache"

# 创建 OPcache 缓存目录并设置权限
if [ ! -d "$OPCACHE_FILE_CACHE_DIR" ]; then
    echo -e "\033[32m创建 OPcache 缓存目录...\033[0m"
    sudo mkdir -p "$OPCACHE_FILE_CACHE_DIR"
    sudo chown -R www-data:www-data "$OPCACHE_FILE_CACHE_DIR"
fi

# 配置 OPcache
if ! grep -q "^opcache.enable=1" "$PHP_INI_FILE"; then
    echo -e "\033[32m启用 OPcache 扩展...请稍等...\033[0m"
    sudo tee -a "$PHP_INI_FILE" > /dev/null <<EOL
[opcache]
opcache.enable=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=5000
opcache.revalidate_freq=5
opcache.save_comments=1
opcache.file_cache=${OPCACHE_FILE_CACHE_DIR}
opcache.file_cache_size=128
opcache.file_cache_only=0
opcache.file_cache_consistency_checks=1
EOL
fi

# 设置时区
TIMEZONE="Asia/Shanghai"

# 更新或添加 date.timezone 配置
if grep -q "^date.timezone" "$PHP_INI_FILE"; then
    sudo sed -i "s#^date.timezone.*#date.timezone = $TIMEZONE#g" "$PHP_INI_FILE"
else
    echo -e "\033[32m设置 date.timezone 为 $TIMEZONE...\033[0m"
    echo "date.timezone = $TIMEZONE" | sudo tee -a "$PHP_INI_FILE" > /dev/null
fi

# 重启 PHP-FPM 服务
sudo systemctl restart php${PHP_VERSION}-fpm

echo -e "\033[32mPHP 配置已更新并重启 PHP-FPM 服务。\033[0m"
