#!/bin/bash

# 更新系统包列表
apt update

# 安装必要的软件包
echo "正在安装 StrongSwan 和 xl2tpd..."
apt install -yq strongswan xl2tpd ppp

# 随机生成用户名、密码和预共享密钥
USERNAME="vpnuser_$(tr -dc A-Za-z0-9 </dev/urandom | head -c 6)"  # 随机生成用户名
PASSWORD="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 10)"       # 随机生成密码
PSK="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)"            # 随机生成预共享密钥

# 配置 StrongSwan
echo "正在配置 StrongSwan..."
cat <<EOF > /etc/ipsec.conf
config setup
    charondebug="ike 2, knl 2, cfg 2"
    uniqueids=no

conn L2TP-PSK
    authby=secret
    pfs=no
    auto=add
    keyexchange=ikev1
    type=transport
    left=%any
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/1701
    ikelifetime=8h
    keylife=1h
    rekeymargin=3m
    keyingtries=1
    dpdaction=clear
    dpddelay=35s
    dpdtimeout=200s
EOF

# 设置预共享密钥
echo "正在设置预共享密钥..."
cat <<EOF > /etc/ipsec.secrets
: PSK "$PSK"
EOF

# 配置 xl2tpd
echo "正在配置 xl2tpd..."
cat <<EOF > /etc/xl2tpd/xl2tpd.conf
[global]
port = 1701

[lns default]
ip range = 192.168.1.10-192.168.1.100  # 为 VPN 客户端分配的 IP 范围
local ip = 192.168.1.1                  # VPN 服务器的 IP 地址
require chap = yes                      # 要求使用 CHAP 认证
refuse pap = yes                        # 拒绝 PAP 认证
require authentication = yes            # 需要认证
name = L2TP-VPN-Server                 # VPN 服务器的名称
ppp debug = yes                         # 启用 PPP 调试
pppoptfile = /etc/ppp/options.xl2tpd   # 指定 PPP 选项文件
length bit = yes                        # 支持长度位
EOF

# 配置 PPP 选项
echo "正在配置 PPP 选项..."
cat <<EOF > /etc/ppp/options.xl2tpd
require-mschap-v2
refuse-mschap
refuse-chap
refuse-pap
ms-dns 8.8.8.8                        # DNS 服务器地址
ms-dns 8.8.4.4                        # 备用 DNS 服务器地址
auth
mtu 1200
mru 1200
lock
proxyarp
connect-delay 5000
EOF

# 添加 VPN 用户
cat <<EOF > /etc/ppp/chap-secrets
# Secrets for authentication using CHAP
# client    server      secret               IP addresses
$USERNAME     L2TP-VPN-Server   "$PASSWORD"     *  # 随机生成的用户名和密码
EOF

# 启动服务
echo "正在启动 StrongSwan 和 xl2tpd 服务..."
systemctl restart strongswan
systemctl restart xl2tpd
systemctl enable strongswan
systemctl enable xl2tpd


# 输出连接信息
echo "L2TP/IPSec VPN 安装和配置完成！"
echo "请使用以下信息进行连接："
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo "预共享密钥: $PSK"
