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

# 生成一个 11 位的随机英文字符串作为路径
RANDOM_PATH=$(cat /dev/urandom | tr -dc 'a-zA-Z' | head -c 11)

# 生成一个随机的私钥
PRIVATE_KEY=$(xray x25519)

# 生成随机的shortIds
SHORT_ID_1=$(openssl rand -hex 8)
SHORT_ID_2=$(openssl rand -hex 8)

# 创建配置文件
create_config() {
    cat > "$config_file" << EOF
{
  "log": {
    "loglevel": "warning"
  },
  "routing": {
    "rules": [
      {
        "port": "443",
        "network": "udp",
        "outboundTag": "block"
      }
    ]
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "security": "reality",
        "realitySettings": {
          "dest": "tesla.com:443",
          "serverNames": [
            "tesla.com",
            "www.tesla.com"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            "$SHORT_ID_1",
            "$SHORT_ID_2"
          ],
          "path": "/$RANDOM_PATH"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF
}

# 显示配置信息
show_inbound_config() {
    local ip=$(curl -s http://ipinfo.io/ip)
    echo -e "${green}Vless 节点链接:${none}"
    echo "vless://$(echo -n "{\"v\":\"2\",\"ps\":\"TK节点定制\",\"add\":\"$ip\",\"port\":443,\"id\":\"$UUID\",\"net\":\"grpc\",\"path\":\"/$RANDOM_PATH\",\"tls\":\"\",\"sni\":\"tesla.com\",\"type\":\"none\",\"host\":\"\",\"fingerprint\":\"chrome\"}" | base64 -w 0)"
}

create_config
show_inbound_config
systemctl restart xray
echo -e "${green}Xray 服务重启成功。${none}"
