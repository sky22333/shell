#!/bin/bash

green='\e[32m'
none='\e[0m'
config_file="/usr/local/etc/xray/config.json"

# 检查并安装 jq
if ! type jq &>/dev/null; then
    apt-get update && apt-get install -y jq
fi

# 检查并安装 uuid-runtime
if ! type uuidgen &>/dev/null; then
    apt-get install -y uuid-runtime
fi

# 检查并安装 xray
if ! type xray &>/dev/null; then
    echo -e "${green}正在安装 xray...${none}"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fi

# 生成一个随机端口号（10000以上）
PORT=$(shuf -i 10000-65535 -n 1)

# 生成一个随机 UUID
UUID=$(uuidgen)

# 生成一个 6 位的随机英文字符串作为路径
RANDOM_PATH=$(cat /dev/urandom | tr -dc 'a-z' | head -c 6)

# 创建配置文件
create_config() {
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
}

# 显示配置信息
show_inbound_config() {
    local ip=$(curl -s http://ipinfo.io/ip)
    echo -e "${green}Vmess-ws节点链接:${none}"
    echo "vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"vmess+ws\",\"add\":\"$ip\",\"port\":$PORT,\"id\":\"$UUID\",\"aid\":\"0\",\"net\":\"ws\",\"path\":\"/$RANDOM_PATH\",\"type\":\"none\",\"host\":\"\",\"tls\":\"\"}" | base64 -w 0)"
}

create_config
show_inbound_config
systemctl restart xray
systemctl enable xray
echo -e "${green}Xray 服务已启动。${none}"
