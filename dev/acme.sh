#!/bin/bash

if [ "$(id -u)" != "0" ]; then
    echo -e "\033[0;31m请以 root 用户运行此脚本\033[0m"
    exit 1
fi

install_requirements() {
    local install_cmd=""
    local pkg_manager=""
    local os_type=$(grep '^ID=' /etc/os-release | cut -d'=' -f2)

    if [ "$os_type" == "ubuntu" ] || [ "$os_type" == "debian" ]; then
        pkg_manager="apt"
        install_cmd="apt install -y"
    elif [ "$os_type" == "centos" ]; then
        pkg_manager="yum"
        install_cmd="yum install -y"
    else
        echo -e "\033[0;31m不支持的操作系统: $os_type\033[0m"
        exit 1
    fi

    if ! command -v lsof &> /dev/null; then
        $install_cmd lsof
    fi

    if ! command -v curl &> /dev/null; then
        $install_cmd curl
    fi

    # 检查并安装 socat
    if ! command -v socat &> /dev/null; then
        echo -e "\033[0;32msocat 未安装，正在安装...\033[0m"
        $install_cmd socat
    else
        echo -e "\033[0;32msocat 已安装\033[0m"
    fi
}

# 生成12位纯英文的随机邮箱
generate_random_email() {
    local random_email=$(tr -dc 'a-z' < /dev/urandom | fold -w 12 | head -n 1)
    echo "${random_email}@gmail.com"
}

check_acme_installation() {
    if ! command -v acme.sh &> /dev/null; then
        echo -e "\033[0;32macme.sh 未安装，正在安装...\033[0m"
        curl https://get.acme.sh | sh
        source ~/.bashrc
    else
        echo -e "\033[0;32macme.sh 已安装\033[0m"
    fi
}

# 检查端口 80 是否被占用，并提供释放端口的选项
check_port_80() {
    local pid
    pid=$(lsof -ti:80)

    if [ -n "$pid" ]; then
        echo -e "\033[0;31m端口 80 已被占用，PID为: $pid\033[0m"
        read -p "是否强制释放端口 80? (Y/n): " response

        case "$response" in 
            [yY][eE][sS]|[yY])
                echo "正在释放端口 80..."
                kill -9 $pid
                ;;
            *)
                echo "未释放端口，脚本将退出。"
                exit 1
                ;;
        esac
    fi
}

register_ca() {
    local ca="$1"
    local email="$2"
    echo -e "\033[0;32m正在注册 CA 机构 $ca 使用电子邮件 $email...\033[0m"
    ~/.acme.sh/acme.sh --register-account -m "$email" --server "$ca"
}

generate_ssl_certificate() {
    local domain_name="$1"
    local ca="$2"
    echo -e "\033[0;32m正在为 $domain_name 生成 SSL 证书...\033[0m"

    ~/.acme.sh/acme.sh --issue --force --standalone -d "$domain_name" --server "$ca"

    if [ $? -ne 0 ]; then
        echo -e "\033[0;31mSSL 证书生成失败\033[0m"
        exit 1
    fi

    local cert_path="/root/.acme.sh/${domain_name}_ecc/fullchain.cer"
    local key_path="/root/.acme.sh/${domain_name}_ecc/${domain_name}.key"

    ~/.acme.sh/acme.sh --install-cert -d "$domain_name" \
        --key-file "$key_path"  \
        --fullchain-file "$cert_path"

    # 打印 fullchain.cer 和 .key 文件的绝对路径
    echo -e "\033[0;32m证书路径: $cert_path\033[0m"
    echo -e "\033[0;32m密钥路径: $key_path\033[0m"
}
# 主流程
install_requirements
echo -e "\033[0;32m请输入您的域名（确保已经解析到本机IP）:\033[0m"
read -p "" domain_name

# 检查端口 80
check_port_80

# 检查证书和密钥是否已经存在
cert_path="/root/.acme.sh/${domain_name}_ecc/fullchain.cer"
key_path="/root/.acme.sh/${domain_name}_ecc/${domain_name}.key"

if [ -f "$cert_path" ] && [ -f "$key_path" ]; then
    echo -e "\033[0;32m证书已存在:\033[0m"
    echo -e "\033[0;32m证书全链路径: $cert_path\033[0m"
    echo -e "\033[0;32m密钥文件路径: $key_path\033[0m"
    exit 0
fi


# 生成随机邮箱
user_email=$(generate_random_email)
echo -e "\033[0;32m生成的邮箱: $user_email\033[0m"

# 检查 acme.sh 安装
check_acme_installation

# CA 机构选择
echo -e "\033[0;32m请选择 CA 机构:\033[0m"
echo -e "\033[0;32m1) Let's Encrypt\033[0m"
echo -e "\033[0;32m2) Buypass\033[0m"
echo -e "\033[0;32m3) ZeroSSL\033[0m"
echo -e "\033[0;32m选择 CA 机构 (回车默认选1):\033[0m"
read -p "" ca_choice

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
