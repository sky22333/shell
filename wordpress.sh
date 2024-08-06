#!/bin/bash

# 检查是否以 root 用户运行
if [ "$(id -u)" != "0" ]; then
    echo "请以 root 用户运行此脚本"
    exit 1
fi

# 检测 Linux 发行版
DISTRO=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
fi

if [ "$DISTRO" != "ubuntu" ] && [ "$DISTRO" != "debian" ]; then
    echo "此脚本仅支持 Ubuntu 和 Debian 发行版。"
    exit 1
fi

PKG_MANAGER="apt-get"
PHP_SERVICE="php7.4-fpm"

install_dir="/var/www/html"
db_name="wp$(date +%s)"
db_user="$db_name"
db_password=$(openssl rand -base64 12)
mysqlrootpass=$(openssl rand -base64 12)

# 检查并创建安装目录
if [ ! -d "$install_dir" ]; then
    echo "安装目录 $install_dir 不存在，正在创建..."
    mkdir -p "$install_dir"
else
    echo "安装目录 $install_dir 已存在"
fi

# 询问用户输入域名和电子邮件地址
read -p "请输入您的域名: " domain_name
read -p "请输入邮箱用于申请证书 : " user_email

# 验证域名和电子邮件地址格式
if ! [[ $domain_name =~ ^[a-zA-Z0-9.-]+$ ]]; then
    echo "域名格式错误。"
    exit 1
fi

if ! [[ $user_email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$ ]]; then
    echo "电子邮件地址格式错误。"
    exit 1
fi

# 安装 Nginx
install_nginx() {
    echo "正在安装 Nginx..."
    $PKG_MANAGER update -y
    $PKG_MANAGER install -y nginx
    systemctl enable nginx
    systemctl start nginx

    # 删除默认的 Nginx 站点配置
    if [ -f /etc/nginx/sites-enabled/default ]; then
        echo "删除默认 Nginx 站点配置..."
        rm -f /etc/nginx/sites-enabled/default
    fi
}

# 安装 MySQL
install_mysql() {
    echo "正在安装 MySQL..."
    $PKG_MANAGER install -y mysql-server mysql-client
    systemctl enable mysql
    systemctl start mysql

    # 配置 MySQL root 用户密码
    mysql --user=root <<-EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$mysqlrootpass';
FLUSH PRIVILEGES;
EOF

    # 检查 MySQL 是否成功启动
    if ! systemctl is-active --quiet mysql; then
        echo "MySQL 服务启动失败。"
        exit 1
    fi

    # 保存 MySQL root 密码
    cat > /root/.my.cnf <<EOF
[client]
user=root
password=$mysqlrootpass
EOF
    chmod 700 /root/.my.cnf
}

# 安装 PHP
install_php() {
    echo "正在安装 PHP..."
    $PKG_MANAGER install -y php-fpm php-mysql
    systemctl enable $PHP_SERVICE
    systemctl start $PHP_SERVICE
}

# 安装 acme.sh
install_acme_sh() {
    echo "正在安装 acme.sh..."
    curl https://get.acme.sh | sh
    source ~/.bashrc
}

# 安装 socat
install_socat() {
    echo "正在安装 socat..."
    $PKG_MANAGER install -y socat
}

# 注册 Let's Encrypt 用于申请证书
register_letsencrypt() {
    echo "正在注册CA机构..."
    ~/.acme.sh/acme.sh --register-account -m $user_email --server letsencrypt
}

# 生成 SSL 证书
generate_ssl_certificate() {
    echo "正在为 $domain_name 生成 SSL 证书..."
    systemctl stop nginx

    # 使用 acme.sh 生成证书
    ~/.acme.sh/acme.sh --issue --standalone -d $domain_name --server letsencrypt

    if [ $? -ne 0 ]; then
        echo "SSL 证书生成失败"
        exit 1
    fi

    ~/.acme.sh/acme.sh --install-cert -d $domain_name \
        --key-file       /etc/ssl/$domain_name.key  \
        --fullchain-file /etc/ssl/$domain_name.cer \
        --reloadcmd     "systemctl restart nginx"
}

# 配置 Nginx
configure_nginx() {
    echo "正在配置 Nginx..."
    cat > /etc/nginx/sites-available/wordpress <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain_name;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain_name;

    ssl_certificate /etc/ssl/$domain_name.cer;
    ssl_certificate_key /etc/ssl/$domain_name.key;

    root $install_dir;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/$PHP_SERVICE.sock;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    ln -s /etc/nginx/sites-available/wordpress /etc/nginx/sites-enabled/
    echo "检查 Nginx 配置文件..."
    nginx -t
    if [ $? -ne 0 ]; then
        echo "Nginx 配置文件错误，请检查 /etc/nginx/nginx.conf"
        exit 1
    fi

    echo "重新启动 Nginx 服务..."
    systemctl restart nginx
    if [ $? -ne 0 ]; then
        echo "Nginx 服务启动失败，请检查"
        exit 1
    fi
}

# 安装和配置 WordPress
install_wordpress() {
    echo "正在安装 WordPress 中文版..."
    wget -O /tmp/latest-zh_CN.tar.gz https://cn.wordpress.org/latest-zh_CN.tar.gz
    tar -C "$install_dir" -zxf /tmp/latest-zh_CN.tar.gz --strip-components=1
    cp "$install_dir/wp-config-sample.php" "$install_dir/wp-config.php"
    sed -i "s/database_name_here/$db_name/g" "$install_dir/wp-config.php"
    sed -i "s/username_here/$db_user/g" "$install_dir/wp-config.php"
    sed -i "s/password_here/$db_password/g" "$install_dir/wp-config.php"
    wget -O - https://api.wordpress.org/secret-key/1.1/salt/ >> "$install_dir/wp-config.php"

    # 创建数据库和用户
    mysql --user=root --password=$mysqlrootpass <<EOF
CREATE DATABASE $db_name CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '$db_user'@'localhost' IDENTIFIED WITH mysql_native_password BY '$db_password';
GRANT ALL ON $db_name.* TO '$db_user'@'localhost';
FLUSH PRIVILEGES;
EOF
}

# 主安装流程
install_nginx
install_mysql
install_php
install_acme_sh
install_socat
register_letsencrypt
generate_ssl_certificate
configure_nginx
install_wordpress

# 输出安装信息
echo "\033[32m WordPress 安装完成，请保存以下重要信息。 \033[0m"
echo "\033[32m 数据库名称：$db_name \033[0m"
echo "\033[32m 数据库用户：$db_user \033[0m"
echo "\033[32m 数据库密码：$db_password \033[0m"
echo "\033[32m MySQL root 密码：$mysqlrootpass \033[0m"
echo "\033[32m nginx配置文件路径 /etc/nginx/nginx.conf \033[0m"
echo "\033[32m 数据库配置文件路径 /root/.my.cnf \033[0m"
echo "\033[32m 站点目录 $install_dir \033[0m"
echo "\033[32m 请访问你的域名进入WordPress \033[0m"
