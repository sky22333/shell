#!/bin/bash
# 一键部署站群多IP节点

# 检查并安装 jq
install_jq() {
    if ! command -v jq &> /dev/null; then
        if [[ -f /etc/debian_version ]]; then
            sudo apt-get update
            sudo apt-get install -y jq
        elif [[ -f /etc/redhat-release ]]; then
            sudo yum install -y epel-release
            sudo yum install -y jq
        else
            echo "无法确定系统发行版，手动安装 jq。"
            exit 1
        fi
    else
        echo "jq 已安装。"
    fi
}

# 检查并安装 Xray core
install_xray() {
    if ! command -v xray &> /dev/null; then
        echo "Xray 未安装，正在安装 Xray..."
        bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install
        echo "Xray 安装完成。"
    else
        echo "Xray 已安装。"
    fi
}

get_public_ipv4() {
    ip -4 addr show | grep inet | grep -v "127.0.0.1" | grep -v "10\." | grep -v "172\." | grep -v "192\.168\." | awk '{print $2}' | cut -d'/' -f1
}

print_node_links() {
    local port=$1
    local id=$2
    local outbound_ip=$3
    local link="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$(hostname)\",\"add\":\"$outbound_ip\",\"port\":\"$port\",\"id\":\"$id\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"/ws\",\"tls\":\"none\"}" | base64 -w 0)"
    echo "端口: $port, 出站 IP: $outbound_ip, 节点链接: $link"
}

# 配置 Xray 配置文件
configure_xray() {
    public_ips=($(get_public_ipv4))
    echo "找到的公网 IPv4 地址: ${public_ips[@]}"
    
    config_file="/usr/local/etc/xray/config.json"
    
    cat > $config_file <<EOF
{
  "inbounds": [],
  "outbounds": [],
  "routing": {
    "rules": []
  }
}
EOF

    port=10001
    for ip in "${public_ips[@]}"; do
        echo "正在配置 IP: $ip 端口: $port"
        
        id=$(uuidgen)

        jq --argjson port $port --arg ip $ip --arg id $id '.inbounds += [{
            "port": $port,
            "protocol": "vmess",
            "settings": {
                "clients": [{
                    "id": $id,
                    "alterId": 0
                }]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "/ws"
                }
            },
            "tag": "in-$port"
        }]' $config_file > temp.json && mv temp.json $config_file
        
        # 添加出站配置 (源进源出)
        jq --argjson port $port --arg ip $ip '.outbounds += [{
            "protocol": "freedom",
            "settings": {},
            "sendThrough": $ip,
            "tag": "out-$port"
        }]' $config_file > temp.json && mv temp.json $config_file
        
        # 入站对应的出站 (源进源出)
        jq --argjson port $port '.routing.rules += [{
            "type": "field",
            "inboundTag": ["in-" + ($port | tostring)],
            "outboundTag": "out-" + ($port | tostring)
        }]' $config_file > temp.json && mv temp.json $config_file

        print_node_links $port $id $ip

        port=$((port + 1))
    done

    echo "Xray 配置完成。"
}

restart_xray() {
    echo "正在重启 Xray 服务..."
    systemctl restart xray
    systemctl enable xray
    echo "Xray 服务已重启。"
}

main() {
    install_jq
    install_xray
    configure_xray
    restart_xray
    echo "部署完成。"
}

main
