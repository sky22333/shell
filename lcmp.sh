#!/bin/bash
# 该脚本引用自https://github.com/teddysun/lcmp
# Linux + Caddy + MariaDB + PHP 安装脚本
# 处理退出信号
trap _exit INT QUIT TERM

cur_dir="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"

# 输出颜色格式
_red() {
    printf '\033[1;31;31m%b\033[0m' "$1"
}
_green() {
    printf '\033[1;31;32m%b\033[0m' "$1"
}
_yellow() {
    printf '\033[1;31;33m%b\033[0m' "$1"
}

# 信息输出函数
_info() {
    printf -- "%s" "[$(date)] $1\n"
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

_exit() {
    printf "\n"
    _red "$0 已被终止。"
    printf "\n"
    exit 1
}

# 检查命令是否存在
_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查操作系统类型
check_sys() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
        debian|ubuntu|centos|rhel)
            return 0
            ;;
        *)
            return 1
            ;;
        esac
    else
        return 1
    fi
}

# 版本比较
version_ge() {
    test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"
}

# 检查内核版本是否大于4.9
check_kernel_version() {
    local kernel_version
    kernel_version=$(uname -r | cut -d- -f1)
    version_ge "${kernel_version}" 4.9
}

# 检查BBR状态
check_bbr_status() {
    local param
    param=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    [[ "${param}" == "bbr" ]]
}

# 检查用户权限
[ ${EUID} -ne 0 ] && _red "此脚本必须以root身份运行!\n" && exit 1

# 检查支持的操作系统
if ! check_sys; then
    _error "不支持的操作系统，请切换为Debian, Ubuntu 或 RHEL/CentOS。"
fi

# 设置MariaDB的root密码
_info "请输入MariaDB的root密码:"
read -r -p "[$(date)] (默认密码: MariaDB22333):" db_pass
[ -z "${db_pass}" ] && db_pass="MariaDB22333"
_info "---------------------------"
_info "密码 = $(_red "${db_pass}")"
_info "---------------------------"

# 选择PHP版本
while true; do
    _info "请选择PHP版本:"
    _info "$(_green 1). PHP 7.4"
    _info "$(_green 2). PHP 8.0"
    _info "$(_green 3). PHP 8.1"
    _info "$(_green 4). PHP 8.2"
    _info "$(_green 5). PHP 8.3"
    read -r -p "[$(date)] 请输入一个数字: (默认2) " php_version
    [ -z "${php_version}" ] && php_version=2
    case "${php_version}" in
    1) php_ver="7.4"; break ;;
    2) php_ver="8.0"; break ;;
    3) php_ver="8.1"; break ;;
    4) php_ver="8.2"; break ;;
    5) php_ver="8.3"; break ;;
    *) _info "输入错误! 请输入1-5的数字" ;;
    esac
done
_info "---------------------------"
_info "PHP版本 = $(_red "${php_ver}")"
_info "---------------------------"

_info "按任意键开始...或按Ctrl+C取消"
char=$(get_char)

# VPS初始化
_info "VPS初始化开始"
_error_detect "rm -f /etc/localtime"
_error_detect "ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime"

# 检查系统类型并安装相关工具
if check_sys rhel; then
    _error_detect "yum install -yq yum-utils epel-release"
    _error_detect "yum-config-manager --enable epel"
    if get_rhelversion 8; then
        yum-config-manager --enable powertools >/dev/null 2>&1 || yum-config-manager --enable PowerTools >/dev/null 2>&1
        _info "设置PowerTools存储库完成"
    fi
    if get_rhelversion 9; then
        _error_detect "yum-config-manager --enable crb"
        _info "设置CRB存储库完成"
    fi
    _error_detect "yum makecache"
    _error_detect "yum install -yq vim tar zip unzip net-tools bind-utils screen git virt-what wget whois firewalld mtr traceroute iftop htop jq tree"
elif check_sys debian || check_sys ubuntu; then
    _error_detect "apt-get update"
    _error_detect "apt-get -yq install lsb-release ca-certificates curl"
    _error_detect "apt-get -yq install vim tar zip unzip net-tools bind9-utils screen git virt-what wget whois mtr traceroute iftop htop jq tree"
fi

# 启用BBR
if check_kernel_version; then
    if ! check_bbr_status; then
        sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
        sed -i '/net.core.rmem_max/d' /etc/sysctl.conf
        cat >>/etc/sysctl.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 2500000
EOF
        sysctl -p >/dev/null 2>&1
        _info "BBR已启用"
    fi
fi

# 设置Caddy
_info "开始安装Caddy"
if check_sys rhel; then
    _error_detect "yum install -yq caddy"
elif check_sys debian || check_sys ubuntu; then
    _error_detect "wget -qO caddy-stable_deb.sh https://dl.cloudsmith.io/public/caddy/stable/setup.deb.sh"
    _error_detect "chmod +x caddy-stable_deb.sh"
    _error_detect "./caddy-stable_deb.sh"
    _error_detect "rm -f caddy-stable_deb.sh"
    _error_detect "apt-get install -y caddy"
fi
_info "Caddy安装完成"

# 设置MariaDB
_info "开始安装MariaDB"
_error_detect "wget -qO mariadb_repo_setup.sh https://downloads.mariadb.com/MariaDB/mariadb_repo_setup"
_error_detect "chmod +x mariadb_repo_setup.sh"
_info "./mariadb_repo_setup.sh --mariadb-server-version=mariadb-10.11"
./mariadb_repo_setup.sh --mariadb-server-version=mariadb-10.11 >/dev/null 2>&1
_error_detect "rm -f mariadb_repo_setup.sh"
if check_sys rhel; then
    _error_detect "yum install -y MariaDB-common MariaDB-server MariaDB-client MariaDB-shared MariaDB-backup"
    mariadb_cnf="/etc/my.cnf.d/server.cnf"
elif check_sys debian || check_sys ubuntu; then
    _error_detect "apt-get install -y mariadb-common mariadb-server mariadb-client mariadb-backup"
    mariadb_cnf="/etc/mysql/mariadb.conf.d/50-server.cnf"
fi
_info "MariaDB安装完成"

# 配置MariaDB
lnum=$(sed -n '/\[mysqld\]/=' "${mariadb_cnf}")
sed -i "${lnum}ainnodb_buffer_pool_size = 100M\nmax_allowed_packet = 1024M\nnet_read_timeout = 3600\nnet_write_timeout = 3600" "${mariadb_cnf}"
lnum=$(sed -n '/\[mariadb\]/=' "${mariadb_cnf}")
sed -i "${lnum}acharacter-set-server = utf8mb4\n\n\[client-mariadb\]\ndefault-character-set = utf8mb4" "${mariadb_cnf}"
_error_detect "systemctl start mariadb"
/usr/bin/mysql -e "grant all privileges on *.* to root@'127.0.0.1' identified by \"${db_pass}\" with grant option;"
/usr/bin/mysql -e "grant all privileges on *.* to root@'localhost' identified by \"${db_pass}\" with grant option;"
/usr/bin/mysql -e "delete from mysql.user where password = '' or password is null;"
/usr/bin/mysql -e "delete from mysql.user where not (user='root') or host not in ('localhost', '127.0.0.1', '::1');"
/usr/bin/mysql -e "delete from mysql.db where db='test' or db='test\_%';"
/usr/bin/mysql -e "flush privileges;"
_error_detect "systemctl enable mariadb"
_info "MariaDB配置完成"

_info "所有步骤已完成!"
