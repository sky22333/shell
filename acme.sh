#!/bin/bash

# 检查是否以 root 用户运行
if [ "$(id -u)" != "0" ]; then
    echo "请以 root 用户运行此脚本"
    exit 1
fi

# 生成更真实的随机邮箱
generate_random_email() {
    local part_one=$(tr -dc 'a-z0-9' < /dev/urandom | fold -w 8 | head -n 1)
    local part_two=$(tr -dc 'a-z0-9' < /dev/urandom | fold -w 4 | head -n 1)
    local part_three=$(tr -dc 'a-z0-9' < /dev/urandom | fold -w 4 | head -n 1)
    echo "${part_one}.${part_two}${part_three}@gmail.com"
}

# 检测 acme.sh 是否安装
check_acme_installation() {
    if ! command -v acme.sh &> /dev/null; then
        echo "acme.sh 未安装，正在安装..."
        curl https://get.acme.sh | sh
        source ~/.bashrc
    else
        echo "acme.sh 已安装"
    fi
}

# 注册 CA 机构
register_ca() {
    local ca="$1"
    local email="$2"
    echo "正在注册 CA 机构 $ca 使用电子邮件 $email..."
    ~/.acme.sh/acme.sh --register-account -m "$email" --server "$ca"
}

# 生成 SSL 证书
generate_ssl_certificate() {
    local domain_name="$1"
    local ca="$2"
    echo "正在为 $domain_name 生成 SSL 证书..."
    systemctl stop nginx

    # 使用 acme.sh 生成证书
    ~/.acme.sh/acme.sh --issue --standalone -d "$domain_name" --server "$ca"

    if [ $? -ne 0 ]; then
        echo "SSL 证书生成失败"
        exit 1
    fi

    local cert_path="/etc/ssl/$domain_name.cer"
    local key_path="/etc/ssl/$domain_name.key"

    ~/.acme.sh/acme.sh --install-cert -d "$domain_name" \
        --key-file "$key_path"  \
        --fullchain-file "$cert_path" \
        --reloadcmd "systemctl restart nginx"

    # 显示证书和密钥的路径
    echo -e "\033[0;32m证书路径: $cert_path"
    echo -e "密钥路径: $key_path\033[0m"
}

# 主流程
read -p "请输入您的域名: " domain_name

# 检查证书和密钥是否已经存在
cert_path="/etc/ssl/$domain_name.cer"
key_path="/etc/ssl/$domain_name.key"

if [ -f "$cert_path" ] && [ -f "$key_path" ]; then
    echo -e "\033[0;32m证书已存在:"
    echo -e "证书路径: $cert_path"
    echo -e "密钥路径: $key_path\033[0m"
    exit 0
fi

# 生成随机邮箱
user_email=$(generate_random_email)
echo "生成的邮箱: $user_email"

# 检查 acme.sh 安装
check_acme_installation

# CA 机构选择
echo "请选择 CA 机构:"
echo "1) Let's Encrypt"
echo "2) Buypass"
echo "3) ZeroSSL"
read -p "选择 CA 机构 (默认: 1): " ca_choice

case $ca_choice in
    2)
        CA="buypass"
        ;;
    3)
        CA="zerossl"
        ;;
    *)
        CA="letsencrypt"
        ;;
esac

register_ca "$CA" "$user_email"
generate_ssl_certificate "$domain_name" "$CA"
