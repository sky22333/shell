#!/bin/bash
# 站群多IP源进源出节点脚本
# 作者sky22333

install_jq() {
    if ! command -v jq &> /dev/null; then
        echo "jq 未安装，正在安装 jq..."
        if [[ -f /etc/debian_version ]]; then
            sudo apt-get update
            sudo apt-get install -yq jq
        elif [[ -f /etc/redhat-release ]]; then
            sudo yum install -y epel-release
            sudo yum install -y jq
        else
            echo "无法确定系统发行版，请手动安装 jq。"
            exit 1
        fi
    else
        echo "jq 已安装。"
    fi
}

install_xray() {
    if ! command -v xray &> /dev/null; then
        echo "Xray 未安装，正在安装 Xray..."
        if ! bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install; then
            echo "Xray 安装失败，请检查网络连接或安装脚本。"
            exit 1
        fi
        echo "Xray 安装完成。"
    else
        echo "Xray 已安装。"
    fi
}

get_public_ipv4() {
    ip -4 addr show | grep inet | grep -vE "127\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|169\.254" | awk '{print $2}' | cut -d'/' -f1
}

print_node_links() {
    local port=$1
    local id=$2
    local outbound_ip=$3
    local link="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$outbound_ip\",\"add\":\"$outbound_ip\",\"port\":\"$port\",\"id\":\"$id\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"/ws\",\"tls\":\"none\"}" | base64 | tr -d '\n')"
    echo -e "端口: $port, 节点链接: \033[32m$link\033[0m"
}

configure_xray() {
    public_ips=($(get_public_ipv4))
    
    if [[ ${#public_ips[@]} -eq 0 ]]; then
        echo "未找到任何公网 IPv4 地址，退出..."
        exit 1
    fi
    
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

    # 配置 inbounds 和 outbounds
    port=10001
    for ip in "${public_ips[@]}"; do
        echo "正在配置 IP: $ip 端口: $port"
        
        id=$(uuidgen)

        jq --argjson port "$port" --arg ip "$ip" --arg id "$id" '.inbounds += [{
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
            "tag": ("in-\($port)")
        }] | .outbounds += [{
            "protocol": "freedom",
            "settings": {},
            "sendThrough": $ip,
            "tag": ("out-\($port)")
        }] | .routing.rules += [{
            "type": "field",
            "inboundTag": ["in-\($port)"],
            "outboundTag": "out-\($port)"
        }]' "$config_file" > temp.json && mv temp.json "$config_file"

        print_node_links "$port" "$id" "$ip"

        port=$((port + 1))
    done

    echo "Xray 配置完成。"
}

restart_xray() {
    echo "正在重启 Xray 服务..."
    if ! systemctl restart xray; then
        echo "Xray 服务重启失败，请检查配置文件。"
        exit 1
    fi
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
