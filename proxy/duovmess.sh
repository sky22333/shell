#!/bin/bash
# 站群多IP源进源出节点脚本vmess+ws协议
# 作者sky22333

install_jq() {
    # 检查 jq 和 uuidgen 是否已安装
    if ! command -v jq &> /dev/null || ! command -v uuidgen &> /dev/null; then
        echo "未找到 jq 或 uuidgen，正在安装依赖..."
        if [[ -f /etc/debian_version ]]; then
            apt update && apt install -yq jq uuid-runtime
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y jq util-linux
        else
            echo "无法确定系统发行版，请手动安装 jq 和 uuid-runtime。"
            exit 1
        fi
    else
        echo "jq 和 uuidgen 都已安装。"
    fi
}

install_xray() {
    if ! command -v xray &> /dev/null; then
        echo "Xray 未安装，正在安装 Xray..."
        if ! bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install --version v1.8.4; then
            echo "Xray 安装失败，请检查网络连接或安装脚本。"
            exit 1
        fi
        echo "Xray 安装完成。"
    else
        echo "Xray 已安装。"
    fi
}

get_public_ipv4() {
    ip -4 addr show | awk '/inet / {ip = $2; sub(/\/.*/, "", ip); if (ip !~ /^127\./ && ip !~ /^10\./ && ip !~ /^192\.168\./ && ip !~ /^169\.254\./ && ip !~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./) print ip}'
}

# 确保 vmess.txt 文件存在，如果不存在则创建
ensure_vmess_file() {
    if [ ! -f /home/vmess.txt ]; then
        echo "vmess.txt 文件不存在，正在创建..."
        touch /home/vmess.txt
    fi
}

print_node_links() {
    local port=$1
    local id=$2
    local outbound_ip=$3
    local link="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$outbound_ip\",\"add\":\"$outbound_ip\",\"port\":\"$port\",\"id\":\"$id\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"/ws\",\"tls\":\"none\"}" | base64 | tr -d '\n')"
    echo -e "端口: $port, 节点链接: \033[32m$link\033[0m"
    
    # 将 vmess 链接保存到 /home/vmess.txt 文件中，每行一个链接
    echo "$link" >> /home/vmess.txt
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
    ensure_vmess_file
    install_jq
    install_xray
    configure_xray
    restart_xray
    echo "部署完成，所有节点信息已保存在 /home/vmess.txt"
}

main
