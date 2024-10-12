#!/bin/bash

# 退出时显示错误
set -e

# 更新系统包列表
apt update

# 安装必要的软件包
echo "正在安装 StrongSwan 和 xl2tpd..."
DEBIAN_FRONTEND=noninteractive apt install -yq strongswan xl2tpd ppp

# 随机生成用户名、密码和预共享密钥
USERNAME="vpnuser_$(tr -dc A-Za-z0-9 </dev/urandom | head -c 6)"
PASSWORD="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)"
PSK="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)"

# 获取公网 IP
PUBLIC_IP=$(curl -s http://ipinfo.io/ip)

# 配置 StrongSwan
echo "正在配置 StrongSwan..."
cat <<EOF > /etc/ipsec.conf
config setup
    charondebug="ike 1, knl 1, cfg 0"
    uniqueids=no

conn L2TP-PSK
    authby=secret
    pfs=no
    auto=add
    keyingtries=3
    rekey=no
    ikelifetime=8h
    keylife=1h
    type=transport
    left=$PUBLIC_IP
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    dpdaction=clear
    dpddelay=30s
    dpdtimeout=120s
EOF

# 设置预共享密钥
echo "正在设置预共享密钥..."
echo ": PSK \"$PSK\"" > /etc/ipsec.secrets

# 配置 xl2tpd
echo "正在配置 xl2tpd..."
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

# 配置 PPP 选项
echo "正在配置 PPP 选项..."
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

# 添加 VPN 用户
echo "$USERNAME * $PASSWORD *" > /etc/ppp/chap-secrets

# 配置 IP 转发
echo "正在配置 IP 转发..."
echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/60-vpn-forward.conf
sysctl -p /etc/sysctl.d/60-vpn-forward.conf

# 配置 NAT
iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o eth0 -j MASQUERADE
iptables-save > /etc/iptables.rules

# 创建一个服务来在启动时恢复 iptables 规则
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

# 重启并启用服务
echo "正在重启并启用服务..."
systemctl restart strongswan
systemctl restart xl2tpd
systemctl enable strongswan
systemctl enable xl2tpd

# 输出连接信息
echo "L2TP/IPSec VPN 安装和配置完成！"
echo "请使用以下信息进行连接："
echo "服务器地址: $PUBLIC_IP"
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo "预共享密钥: $PSK"
