#!/bin/bash

# 输出颜色
_red() {
    printf '\033[1;31;31m%b\033[0m' "$1"
}

_green() {
    printf '\033[1;31;32m%b\033[0m' "$1"
}

_yellow() {
    printf '\033[1;31;33m%b\033[0m' "$1"
}

_printargs() {
    printf -- "%s" "[$(date)] "
    printf -- "%s" "$1"
    printf "\n"
}

_info() {
    _printargs "$@"
}

_warn() {
    printf -- "%s" "[$(date)] "
    _yellow "$1"
    printf "\n"
}

_error() {
    printf -- "%s" "[$(date)] "
    _red "$1"
    printf "\n"
    exit 2
}

_exists() {
    command -v "$1" >/dev/null 2>&1
}

_check_os() {
    if grep -Eqi "debian" /etc/issue; then
        OS="debian"
    elif grep -Eqi "ubuntu" /etc/issue; then
        OS="ubuntu"
    elif grep -Eqi "debian" /proc/version; then
        OS="debian"
    elif grep -Eqi "ubuntu" /proc/version; then
        OS="ubuntu"
    else
        _error "不支持的操作系统。本脚本仅支持 Debian 或 Ubuntu。"
    fi
}

# 检查脚本是否以 root 用户身份运行
[ ${EUID} -ne 0 ] && _red "此脚本必须以 root 用户身份运行！" && exit 1

# 检查操作系统
_check_os

# 选择 PHP 版本
while true; do
    _info "请选择一个 PHP 版本："
    _info "$(_green 1). PHP 7.4"
    _info "$(_green 2). PHP 8.0"
    _info "$(_green 3). PHP 8.1"
    _info "$(_green 4). PHP 8.2"
    _info "$(_green 5). PHP 8.3"
    read -r -p "[$(date)] 请输入一个数字: (默认 4) " php_version
    [ -z "${php_version}" ] && php_version=4
    case "${php_version}" in
    1)
        php_ver="7.4"
        break
        ;;
    2)
        php_ver="8.0"
        break
        ;;
    3)
        php_ver="8.1"
        break
        ;;
    4)
        php_ver="8.2"
        break
        ;;
    5)
        php_ver="8.3"
        break
        ;;
    *)
        _info "输入错误！请仅输入数字 1 2 3 4 5"
        ;;
    esac
done

_info "---------------------------"
_info "PHP 版本 = $(_red "${php_ver}")"
_info "---------------------------"

_info "开始安装 PHP"

# 安装 PHP 和扩展
if [ "${OS}" == "debian" ] || [ "${OS}" == "ubuntu" ]; then
    _error_detect "apt-get update"
    _error_detect "apt-get -y install lsb-release ca-certificates curl"
    
    # 添加 PHP 仓库
    if [ "${OS}" == "debian" ]; then
        _error_detect "curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg"
        echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" >/etc/apt/sources.list.d/php.list
    elif [ "${OS}" == "ubuntu" ]; then
        _error_detect "add-apt-repository -y ppa:ondrej/php"
    fi

    _error_detect "apt-get update"
    
    # 安装 PHP 及常用扩展
    _error_detect "apt-get install -y php${php_ver}-fpm php${php_ver}-cli php${php_ver}-common php${php_ver}-opcache php${php_ver}-readline"
    _error_detect "apt-get install -y php${php_ver}-bcmath php${php_ver}-gd php${php_ver}-imap php${php_ver}-mysql php${php_ver}-dba php${php_ver}-mongodb php${php_ver}-sybase"
    _error_detect "apt-get install -y php${php_ver}-pgsql php${php_ver}-odbc php${php_ver}-enchant php${php_ver}-gmp php${php_ver}-intl php${php_ver}-ldap php${php_ver}-snmp php${php_ver}-soap"
    _error_detect "apt-get install -y php${php_ver}-mbstring php${php_ver}-curl php${php_ver}-pspell php${php_ver}-xml php${php_ver}-zip php${php_ver}-bz2 php${php_ver}-lz4 php${php_ver}-zstd"
    _error_detect "apt-get install -y php${php_ver}-tidy php${php_ver}-sqlite3 php${php_ver}-imagick php${php_ver}-grpc php${php_ver}-yaml php${php_ver}-uuid"
    
    _info "PHP 安装完成"
else
    _error "不支持的操作系统。本脚本仅支持 Debian 或 Ubuntu。"
fi

exit 0