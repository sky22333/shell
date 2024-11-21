#!/bin/bash

# 颜色代码
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 检查Root权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}必须以root权限运行此脚本${NC}"
   exit 1
fi

# 生成随机字符串
generate_random_string() {
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$1"
}

# 主安装函数
install_l2tp_vpn() {
    # 配置参数
    VPN_SERVER_IP=$(curl -s http://ipinfo.io/ip)
    VPN_PSK=$(generate_random_string 16)
    VPN_USERNAME=$(generate_random_string 8)
    VPN_PASSWORD=$(generate_random_string 12)

    # 更新和安装依赖
    apt-get update
    apt-get install -y strongswan xl2tpd ppp

    # IPsec配置
    cat > /etc/ipsec.conf << EOF
config setup
    charondebug="all"
    uniqueids=never

conn l2tp-psk
    authby=secret
    left=%defaultroute
    leftid=$VPN_SERVER_IP
    leftauth=psk
    leftprotoport=17/1701
    leftsendcert=never
    right=%any
    rightauth=psk
    rightprotoport=17/1701
    rightsourceip=10.0.0.0/24
    auto=add
EOF

    cat > /etc/ipsec.secrets << EOF
: PSK "$VPN_PSK"
EOF

    # xl2tpd配置
    cat > /etc/xl2tpd/xl2tpd.conf << EOF
[global]
port = 1701

[lns default]
ip range = 10.0.0.2-10.0.0.254
local ip = 10.0.0.1
require chap = yes
refuse pap = yes
require authentication = yes
name = L2TPServer
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

    cat > /etc/ppp/options.xl2tpd << EOF
ipcp-accept-local
ipcp-accept-remote
require-mschap-v2
ms-dns 8.8.8.8
ms-dns 1.1.1.1
noccp
auth
hide-password
nodefaultroute
usepeerdns
name l2tpd
plugin /usr/lib/pppd/*/libplugin.so
EOF

    cat > /etc/ppp/chap-secrets << EOF
$VPN_USERNAME * $VPN_PASSWORD *
EOF

    # 设置权限
    chmod 600 /etc/ipsec.secrets /etc/ppp/chap-secrets

    # 重启服务(使用完整路径)
    /usr/sbin/service strongswan-starter restart
    /usr/sbin/service xl2tpd restart

    # 输出配置信息
    echo -e "${GREEN}================================================================"
    echo -e "L2TP/IPsec VPN连接详情："
    echo -e "服务器IP: $VPN_SERVER_IP"
    echo -e "用户名: $VPN_USERNAME"
    echo -e "密码: $VPN_PASSWORD"
    echo -e "预共享密钥: $VPN_PSK"
    echo -e "================================================================${NC}"

    # 保存连接信息到文件
    cat > /root/vpn_credentials.txt << EOF
服务器IP: $VPN_SERVER_IP
用户名: $VPN_USERNAME
密码: $VPN_PASSWORD
预共享密钥: $VPN_PSK
EOF
}

# 执行安装
install_l2tp_vpn
