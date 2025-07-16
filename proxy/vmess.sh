#!/bin/bash

# 定义变量
SERVER_IP="192.168.12.23"           # 目标服务器的IP地址
SERVER_PASSWORD="password"         # 目标服务器的登录密码
NODE_NAME="美国独享"                # 用于标识节点的名称
TARGET_DIR="/home/xray.txt"

green='\e[32m'
none='\e[0m'
config_file="/usr/local/etc/xray/config.json"

# 检查并安装依赖项
install_dependencies() {
    if ! type jq &>/dev/null || ! type uuidgen &>/dev/null || ! type sshpass &>/dev/null; then
        echo -e "${green}正在安装 jq, uuid-runtime 和 sshpass...${none}"
        apt update && apt install -yq jq uuid-runtime sshpass
    fi

    if ! type xray &>/dev/null; then
        echo -e "${green}正在安装 xray...${none}"
        bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install --version v1.8.4
    fi
}

# 生成配置和传输逻辑
configure_and_transfer() {
    PORT=$(shuf -i 10000-65535 -n 1)
    UUID=$(uuidgen)
    RANDOM_PATH=$(cat /dev/urandom | tr -dc 'a-z' | head -c 6)

    cat > "$config_file" << EOF
{
    "inbounds": [
        {
            "port": $PORT,
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID"
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "/$RANDOM_PATH"
                }
            },
            "listen": "0.0.0.0"
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {}
        }
    ],
    "routing": {
        "rules": [
            {
                "type": "field",
                "inboundTag": ["inbound0"],
                "outboundTag": "direct"
            }
        ]
    }
}
EOF

    local ip=$(curl -s http://ipinfo.io/ip)
    local config="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$NODE_NAME\",\"add\":\"$ip\",\"port\":$PORT,\"id\":\"$UUID\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"/$RANDOM_PATH\",\"type\":\"none\",\"host\":\"\",\"tls\":\"\"}" | base64 -w 0)"
    echo -e "${green}Vmess-ws节点链接:${none}"
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
