#!/bin/bash
# 站群多IP源进源出节点脚本sk5协议

# 生成随机8位数的用户名和密码
generate_random_string() {
    local length=8
    tr -dc A-Za-z0-9 </dev/urandom | head -c $length
}

install_jq() {
    if ! command -v jq &> /dev/null; then
        echo "jq 未安装，正在安装 jq..."
        if [[ -f /etc/debian_version ]]; then
            apt update && apt install -yq jq
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y epel-release jq
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
        if ! bash <(curl -sSL https://gh-proxy.com/https://github.com/sky22333/shell/raw/main/proxy/xray.sh); then
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

# 确保 socks.txt 文件存在，如果不存在则创建
ensure_socks_file_exists() {
    if [ ! -f /home/socks.txt ]; then
        echo "socks.txt 文件不存在，正在创建..."
        touch /home/socks.txt
    fi
}

print_node_info() {
    local ip=$1
    local port=$2
    local username=$3
    local password=$4
    local outfile=${5:-/home/socks.txt}
    echo -e " IP: \033[32m$ip\033[0m 端口: \033[32m$port\033[0m 用户名: \033[32m$username\033[0m 密码: \033[32m$password\033[0m"
    echo "$ip $port $username $password" >> "$outfile"
}

configure_xray() {
    public_ips=($(get_public_ipv4))
    
    if [[ ${#public_ips[@]} -eq 0 ]]; then
        echo "未找到额外IP地址，退出..."
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
        
        # 此处用户名和密码可以改为固定值
        username=$(generate_random_string)
        password=$(generate_random_string)

        jq --argjson port "$port" --arg ip "$ip" --arg username "$username" --arg password "$password" '.inbounds += [{
            "port": $port,
            "protocol": "socks",
            "settings": {
                "auth": "password",
                "accounts": [{
                    "user": $username,
                    "pass": $password
                }],
                "udp": true,
                "ip": "0.0.0.0"
            },
            "streamSettings": {
                "network": "tcp"
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

        print_node_info "$ip" "$port" "$username" "$password"

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

add_mode=false
if [[ "$1" == "-add" ]]; then
    add_mode=true
fi

main() {
    ensure_socks_file_exists
    install_jq
    install_xray
    if $add_mode; then
        add_xray_nodes
    else
        config_file="/usr/local/etc/xray/config.json"
        if [[ -f $config_file ]]; then
            if jq -e '.inbounds[]? | select(.port==10001)' "$config_file" >/dev/null; then
                echo "检测到已有节点配置，无需重复生成，如需添加节点请添加 -add命令"
                exit 0
            fi
        fi
        configure_xray
        restart_xray
        echo "部署完成，所有节点信息已保存到 /home/socks.txt"
    fi
}

add_xray_nodes() {
    public_ips=($(get_public_ipv4))
    config_file="/usr/local/etc/xray/config.json"
    if [[ ! -f $config_file ]]; then
        echo "Xray 配置文件不存在，无法追加。"
        exit 1
    fi
    # 获取已存在的IP
    existing_ips=($(jq -r '.outbounds[].sendThrough' "$config_file" | grep -v null))
    # 过滤出未添加的新IP
    new_ips=()
    for ip in "${public_ips[@]}"; do
        found=false
        for eip in "${existing_ips[@]}"; do
            if [[ "$ip" == "$eip" ]]; then
                found=true
                break
            fi
        done
        if ! $found; then
            new_ips+=("$ip")
        fi
    done
    if [[ ${#new_ips[@]} -eq 0 ]]; then
        echo "没有新IP需要追加。"
        return
    fi
    # 生成北京时间文件名
    beijing_time=$(TZ=Asia/Shanghai date +"%Y%m%d_%H%M%S")
    newfile="/home/socks_add_${beijing_time}.txt"
    touch "$newfile"
    # 找到当前最大端口
    last_port=$(jq -r '.inbounds[].port' "$config_file" | sort -n | tail -1)
    if [[ -z "$last_port" || "$last_port" == "null" ]]; then
        port=10001
    else
        port=$((last_port + 1))
    fi
    for ip in "${new_ips[@]}"; do
        echo "追加 IP: $ip 端口: $port"
        username=$(generate_random_string)
        password=$(generate_random_string)
        jq --argjson port "$port" --arg ip "$ip" --arg username "$username" --arg password "$password" '.inbounds += [{
            "port": $port,
            "protocol": "socks",
            "settings": {
                "auth": "password",
                "accounts": [{
                    "user": $username,
                    "pass": $password
                }],
                "udp": true,
                "ip": "0.0.0.0"
            },
            "streamSettings": {
                "network": "tcp"
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
        print_node_info "$ip" "$port" "$username" "$password" "$newfile"
        port=$((port + 1))
    done
    echo "Xray 追加完成，新增节点信息已保存到 $newfile"
    restart_xray
}

main
