#!/bin/bash
# php安装脚本

# 输出颜色
_red() { printf '\033[1;31;31m%b\033[0m\n' "$1"; }
_green() { printf '\033[1;31;32m%b\033[0m\n' "$1"; }
_yellow() { printf '\033[1;31;33m%b\033[0m\n' "$1"; }

_info() { printf "%s\n" "$1"; }
_error() { _red "$1"; exit 2; }
_exists() { command -v "$1" >/dev/null 2>&1; }
_error_detect() { "$@" || _error "命令执行失败: $*"; }

_check_os() {
    if grep -Eqi "debian|ubuntu" /etc/issue || grep -Eqi "debian|ubuntu" /proc/version; then
        OS="debian"
    else
        _error "不支持的操作系统。本脚本仅支持 Debian 或 Ubuntu。"
    fi
}

# 检查操作系统
_check_os

# 设置 PATH
export PATH=$PATH:/usr/bin:/usr/sbin

# 选择 PHP 版本
php_versions=("7.4" "8.0" "8.1" "8.2" "8.3")
_info "请选择一个 PHP 版本："
for i in "${!php_versions[@]}"; do
    _info "$(_green "$(($i + 1))")：PHP ${php_versions[$i]}"
done

read -r -p "[默认 4] 请输入一个数字: " php_version
php_version=${php_versions[$((php_version-1))]:-8.2}

_info "---------------------------"
_info "PHP 版本 = $(_green "${php_version}")"
_info "---------------------------"

_info "开始安装 PHP"

# 安装 PHP 和扩展
_error_detect apt update
_error_detect apt -yq install lsb-release ca-certificates curl

# 添加 PHP 仓库
if [ "$OS" == "debian" ]; then
    _error_detect curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
    echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" >/etc/apt/sources.list.d/php.list
else
    _error_detect add-apt-repository -yq ppa:ondrej/php
fi

# 安装 PHP 及常用扩展
_error_detect apt update
_error_detect apt install -yq \
    php${php_version}-fpm php${php_version}-mysql php${php_version}-curl php${php_version}-json \
    php${php_version}-cgi php${php_version}-mbstring php${php_version}-xml php${php_version}-gd \
    php${php_version}-xmlrpc php${php_version}-soap php${php_version}-intl php${php_version}-opcache \
    php${php_version}-zip

_info "PHP 安装完成"

exit 0
