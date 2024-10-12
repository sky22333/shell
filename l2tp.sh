#!/bin/bash

# 退出时显示错误
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 函数定义
print_info() {
    echo -e "${YELLOW}[INFO] $1${NC}"
}

print_success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

check_service_status() {
    if systemctl is-active --quiet $1; then
        print_success "$1 服务正在运行"
    else
        print_error "$1 服务未运行"
        exit 1
    fi
}

# 检测系统类型
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
else
    print_error "无法检测操作系统类型，脚本可能无法正常工作。"
    exit 1
fi

print_info "检测到的操作系统: $OS"

# 更新系统包列表
print_info "正在更新系统包列表..."
if apt update; then
    print_success "系统包列表更新成功"
else
    print_error "系统包列表更新失败"
    exit 1
fi

# 安装必要的软件包
print_info "正在安装 StrongSwan 和 xl2tpd..."
if DEBIAN_FRONTEND=noninteractive apt install -yq strongswan strongswan-pki libcharon-extra-plugins xl2tpd ppp curl; then
    print_success "StrongSwan 和 xl2tpd 安装成功"
else
    print_error "StrongSwan 和 xl2tpd 安装失败"
    exit 1
fi

# 随机生成用户名、密码和预共享密钥
USERNAME="vpnuser_$(tr -dc A-Za-z0-9 </dev/urandom | head -c 6)"
PASSWORD="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)"
PSK="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)"

# 获取公网 IP
print_info "正在获取公网 IP..."
PUBLIC_IP=$(curl -s http://ipinfo.io/ip)
if [ -z "$PUBLIC_IP" ]; then
    print_error "无法获取公网 IP"
    exit 1
else
    print_success "成功获取公网 IP: $PUBLIC_IP"
fi

# 配置 StrongSwan
print_info "正在配置 StrongSwan..."
cat <<EOF > /etc/ipsec.conf
config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no

conn L2TP-PSK
    authby=secret
    auto=add
    keyingtries=3
    rekey=no
    ikelifetime=8h
    keylife=1h
    type=transport
    left=%any
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    dpdaction=clear
    dpddelay=30s
    dpdtimeout=120s
    ike=aes256-sha256-modp2048!
    esp=aes256-sha256!
EOF
print_success "StrongSwan 配置完成"

# 设置预共享密钥
print_info "正在设置预共享密钥..."
echo ": PSK \"$PSK\"" > /etc/ipsec.secrets
print_success "预共享密钥设置完成"

# 配置 xl2tpd
print_info "正在配置 xl2tpd..."
cat <<EOF > /etc/xl2tpd/xl2tpd.conf
[global]
port = 1701

[lns default]
ip range = 10.10.10.10-10.10.10.200
local ip = 10.10.10.1
require chap = yes
refuse pap = yes
require authentication = yes
name = L2TP-VPN-Server
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF
print_success "xl2tpd 配置完成"

# 配置 PPP 选项
print_info "正在配置 PPP 选项..."
cat <<EOF > /etc/ppp/options.xl2tpd
ipcp-accept-local
ipcp-accept-remote
ms-dns 8.8.8.8
ms-dns 8.8.4.4
noccp
auth
mtu 1280
mru 1280
proxyarp
lcp-echo-failure 4
lcp-echo-interval 30
connect-delay 5000
EOF
print_success "PPP 选项配置完成"

# 添加 VPN 用户
print_info "正在添加 VPN 用户..."
echo "$USERNAME * $PASSWORD *" > /etc/ppp/chap-secrets
print_success "VPN 用户添加完成"

# 配置 IP 转发
print_info "正在配置 IP 转发..."
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/60-vpn-forward.conf
sysctl -p /etc/sysctl.d/60-vpn-forward.conf
print_success "IP 转发配置完成"

# 配置 NAT
print_info "正在配置 NAT..."
DEFAULT_IFACE=$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)
iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o $DEFAULT_IFACE -j MASQUERADE
iptables-save > /etc/iptables.rules
print_success "NAT 配置完成"

# 创建一个服务来在启动时恢复 iptables 规则
print_info "正在创建 iptables 恢复服务..."
cat <<EOF > /etc/systemd/system/iptables-restore.service
[Unit]
Description=Restore iptables rules
Before=network-online.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables.rules

[Install]
WantedBy=multi-user.target
EOF
systemctl enable iptables-restore
print_success "iptables 恢复服务创建完成"

# 重启并启用服务
print_info "正在重启并启用服务..."
if [[ "$OS" == *"Ubuntu"* ]]; then
    systemctl restart strongswan
    systemctl enable strongswan
elif [[ "$OS" == *"Debian"* ]]; then
    systemctl restart strongswan-starter
    systemctl enable strongswan-starter
else
    print_info "未知的操作系统，尝试重启 strongswan 服务..."
    systemctl restart strongswan || systemctl restart strongswan-starter
    systemctl enable strongswan || systemctl enable strongswan-starter
fi

systemctl restart xl2tpd
systemctl enable xl2tpd

# 检查服务状态
if [[ "$OS" == *"Ubuntu"* ]]; then
    check_service_status "strongswan"
elif [[ "$OS" == *"Debian"* ]]; then
    check_service_status "strongswan-starter"
else
    if systemctl is-active --quiet strongswan; then
        check_service_status "strongswan"
    elif systemctl is-active --quiet strongswan-starter; then
        check_service_status "strongswan-starter"
    else
        print_error "strongSwan 服务未运行"
        exit 1
    fi
fi

check_service_status "xl2tpd"

# 输出连接信息
print_success "L2TP/IPSec VPN 安装和配置完成！"
echo -e "${GREEN}请使用以下信息进行连接：${NC}"
echo -e "${GREEN}服务器地址: $PUBLIC_IP${NC}"
echo -e "${GREEN}用户名: $USERNAME${NC}"
echo -e "${GREEN}密码: $PASSWORD${NC}"
echo -e "${GREEN}预共享密钥: $PSK${NC}"
