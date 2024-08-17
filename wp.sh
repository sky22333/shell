#!/bin/bash
# 一键部署WordPress脚本

# 检查是否已经安装 WordPress
if [ -f "/var/www/html/wordpress/wp-config.php" ]; then
    echo -e "\033[32mWordPress 已经安装。\033[0m"
    echo -e "\033[33m如需重新安装，请先删除 /var/www/html/wordpress 并备份相关数据。\033[0m"
    exit 0
fi

# 使用黄色字体提示用户输入域名
while true; do
    # 提示用户输入域名
    echo -e "\033[33m请输入您的域名(确保已经解析到本机): \033[0m"
    read DOMAIN
    
    # 显示用户输入的域名并要求确认
    echo -e "\033[32m您输入的域名是: \033[0m$DOMAIN"
    echo -e "\033[33m请确认这个域名是否正确 (yes/no): \033[0m"
    read CONFIRM
    
    # 判断用户的确认输入
    if [[ "$CONFIRM" == "yes" || "$CONFIRM" == "y" ]]; then
        echo -e "\033[32m域名确认成功: $DOMAIN\033[0m"
        break
    else
        echo -e "\033[31m请重新输入域名。\033[0m"
    fi
done

# 更新系统包
echo -e "\033[33m正在更新系统包...首次更新可能较慢...请耐心等待。。。\033[0m"
sudo apt update > /dev/null 2>&1 && sudo apt upgrade -y > /dev/null 2>&1

# 安装必要的软件包
echo -e "\033[33m正在安装必要的软件包...首次安装可能较慢...请耐心等待。。。\033[0m"
sudo apt install -y mariadb-server php php-mysql php-fpm php-curl php-json php-cgi php-mbstring php-xml php-gd php-xmlrpc php-soap php-intl php-zip wget unzip > /dev/null 2>&1

# 启动并启用MariaDB
sudo systemctl start mariadb
sudo systemctl enable mariadb

# MariaDB安全设置
sudo mysql_secure_installation <<EOF

y
y
y
y
y
EOF

# 创建WordPress数据库和用户
DB_NAME="wordpress"
DB_USER="wpuser"
DB_PASSWORD=$(openssl rand -base64 12)


# 删除旧的用户（如果存在）并创建新用户
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

# 设置文件权限
sudo chown -R www-data:www-data /var/www/html/wordpress
sudo find /var/www/html/wordpress/ -type d -exec chmod 750 {} \;
sudo find /var/www/html/wordpress/ -type f -exec chmod 640 {} \;

# 安装Caddy
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy

# 配置Caddy
sudo bash -c "cat > /etc/caddy/Caddyfile" <<EOF
$DOMAIN {
    root * /var/www/html/wordpress
    encode zstd gzip
    php_fastcgi unix//run/php/php7.4-fpm.sock
    file_server

    @static {
        path *.css *.js *.gif *.jpg *.jpeg *.png *.svg *.woff *.woff2
        file
    }
    header @static Cache-Control "public, max-age=3153600, immutable"
    header Cache-Control "public, max-age=3600"
}
EOF

# 启动Caddy
sudo systemctl restart caddy

# 绿色字体打印数据库信息
echo -e "\033[32m数据库信息: \033[0m"
echo -e "\033[32m数据库名: ${DB_NAME}\033[0m"
echo -e "\033[32m用户名: ${DB_USER}\033[0m"
echo -e "\033[32m密码: ${DB_PASSWORD}\033[0m"
echo -e "\033[32m您的wordpress站点已经部署完成，请记录好相关信息。\033[0m"
