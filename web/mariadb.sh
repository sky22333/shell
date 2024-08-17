#!/bin/bash

# MariaDB安装脚本

_info() {
    echo -e "\e[32m$1\e[0m"
}

_error() {
    echo -e "\e[31m错误: $1\e[0m"
    exit 1
}

_error_detect() {
    if ! eval "$1"; then
        _error "执行命令 ($1) 失败"
    fi
}

install_mariadb() {
    _info "开始安装MariaDB"
    _error_detect "apt update"
    _error_detect "apt install -yq mariadb-server"
    _error_detect "systemctl start mariadb"
    _error_detect "systemctl enable mariadb"
    _info "MariaDB安装完成"
}

configure_database() {
    read -r -p "请输入新数据库名称: " database_name
    read -r -p "请输入新数据库用户密码: " mysql_password

    cat >/tmp/.add_mysql.sql<<EOF
CREATE USER '${database_name}'@'localhost' IDENTIFIED BY '${mysql_password}';
CREATE USER '${database_name}'@'127.0.0.1' IDENTIFIED BY '${mysql_password}';
GRANT USAGE ON *.* TO '${database_name}'@'localhost' IDENTIFIED BY '${mysql_password}';
GRANT USAGE ON *.* TO '${database_name}'@'127.0.0.1' IDENTIFIED BY '${mysql_password}';
CREATE DATABASE IF NOT EXISTS ${database_name};
GRANT ALL PRIVILEGES ON ${database_name}.* TO '${database_name}'@'localhost';
GRANT ALL PRIVILEGES ON ${database_name}.* TO '${database_name}'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF

    if mysql -uroot -p"${db_root_password}" < /tmp/.add_mysql.sql; then
        _info "数据库 ${database_name} 创建成功"
    else
        _error "数据库 ${database_name} 创建失败"
    fi

    rm -f /tmp/.add_mysql.sql
}

print_db_info() {
    _info "数据库信息："
    _info "数据库名称：${database_name}"
    _info "数据库用户：${database_name}"
    _info "数据库密码：${mysql_password}"
    _info "请妥善保管以上信息"
}

_info "MariaDB 安装脚本开始执行"

install_mariadb
configure_database
print_db_info

_info "MariaDB安装、配置和数据库创建已完成"
