#!/bin/bash

# 检查并安装 jq（如果未安装）
install_jq() {
    if ! command -v jq &> /dev/null; then
        echo "jq 未安装，正在安装 jq..."
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

# 检查并安装 Xray core（如果未安装）
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

# 获取所有公网 IPv4 地址
get_public_ipv4() {
    ip -4 addr show | grep inet | grep -vE "127\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.|169\.254" | awk '{print $2}' | cut -d'/' -f1
}

# 打印节点链接
print_node_links() {
    local port=$1
    local id=$2
    local outbound_ip=$3
    local link="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$outbound_ip\",\"add\":\"$outbound_ip\",\"port\":\"$port\",\"id\":\"$id\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"/ws\",\"tls\":\"none\"}" | base64 | tr -d '\n')"
    echo -e "\033[32m端口: $port, 节点链接: $link\033[0m"
}

# 配置 Xray 配置文件
configure_xray() {
    public_ips=($(get_public_ipv4))
    
    if [[ ${#public_ips[@]} -eq 0 ]]; then
        echo "未找到任何公网 IPv4 地址，退出..."
        exit 1
    fi
    
    echo "找到的公网 IPv4 地址: ${public_ips[@]}"
    
    # Xray 配置文件路径
    config_file="/usr/local/etc/xray/config.json"
    
    # 基础配置
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
        
        # 生成 UUID
        id=$(uuidgen)

        # 使用一次 jq 完成 inbounds 和 outbounds 的更新
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

        # 打印节点链接
        print_node_links "$port" "$id" "$ip"

        # 端口递增
        port=$((port + 1))
    done

    echo "Xray 配置完成。"
}

# 重启 Xray 服务
restart_xray() {
    echo "正在重启 Xray 服务..."
    if ! systemctl restart xray; then
        echo "Xray 服务重启失败，请检查配置文件。"
        exit 1
    fi
    systemctl enable xray
    echo "Xray 服务已重启。"
}

# 主函数
main() {
    install_jq
    install_xray
    configure_xray
    restart_xray
    echo "部署完成。"
}

# 执行主函数
main
