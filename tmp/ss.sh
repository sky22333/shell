#!/bin/bash

# 定义变量
SERVER_IP="192.168.12.23"           # 目标服务器的IP地址
SERVER_PASSWORD="password"         # 目标服务器的登录密码
NODE_NAME="美国定制"                # 用于标识节点的名称
TARGET_DIR="/home/xray.txt"

green='\e[32m'
none='\e[0m'
config_file="/usr/local/etc/xray/config.json"

# 检查并安装依赖项
install_dependencies() {
    if ! type jq &>/dev/null; then
        echo -e "${green}正在安装 jq...${none}"
        apt-get update && apt-get install -y jq
    fi
    if ! type sshpass &>/dev/null; then
        echo -e "${green}正在安装 sshpass...${none}"
        apt-get install -y sshpass
    fi
    if ! type xray &>/dev/null; then
        echo -e "${green}正在安装 xray...${none}"
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    fi
}

# 生成配置和传输逻辑
configure_and_transfer() {
    local PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z' | fold -w 18 | head -n 1)
    
    cat > "$config_file" << EOF
{
    "inbounds": [
        {
            "port": 9527,
            "protocol": "shadowsocks",
            "settings": {
                "method": "aes-256-gcm",
                "password": "$PASSWORD"
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {}
        }
    ]
}
EOF
    local ip=$(curl -s http://ipinfo.io/ip)
    local config="ss://$(echo -n "aes-256-gcm:$PASSWORD" | base64 -w 0)@$ip:9527#$NODE_NAME"
    echo -e "${green}Shadowsocks 节点配置信息:${none}"
    echo $config
    echo $config > /tmp/xray_config.txt
    sshpass -p "$SERVER_PASSWORD" ssh -o StrictHostKeyChecking=no root@$SERVER_IP "cat >> $TARGET_DIR" < /tmp/xray_config.txt
}

# 主执行逻辑
install_dependencies
configure_and_transfer
systemctl restart xray
systemctl enable xray
echo -e "${green}Xray 服务已启动。${none}"
