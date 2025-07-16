#!/bin/bash
# sing-box站群多IP源进源出节点脚本 支持sk5和vless+tcp协议

# 生成随机8位数的用户名和密码
generate_random_string() {
    local length=8
    tr -dc A-Za-z0-9 </dev/urandom | head -c $length
}

# 生成随机UUID
generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# 获取当前北京时间，精确到秒
get_beijing_time() {
    TZ=Asia/Shanghai date +"%Y年%m月%d日%H点%M分%S秒"
}

# 全局变量，保存当前操作使用的输出文件名
OUTPUT_FILE=""

# 初始化输出文件名
init_output_file() {
    OUTPUT_FILE="/home/$(get_beijing_time).txt"
    # 确保文件存在并清空内容
    touch "$OUTPUT_FILE"
    > "$OUTPUT_FILE"
    echo "将使用输出文件: $OUTPUT_FILE"
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
    if ! command -v sing-box &> /dev/null; then
        echo "sing-box 未安装，正在安装 sing-box..."
        VERSION="1.11.5"
        curl -Lo sing-box.deb "https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box_${VERSION}_linux_amd64.deb"
        if ! dpkg -i sing-box.deb; then
            echo "sing-box 安装失败，请检查dpkg输出。"
            rm -f sing-box.deb
            exit 1
        fi
        rm -f sing-box.deb
        echo "sing-box 安装完成。"
    else
        echo "sing-box 已安装。"
    fi
}

# 检查是否已有节点配置
check_existing_nodes() {
    local config_file="/etc/sing-box/config.json"
    
    # 如果配置文件不存在，则没有节点配置
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    
    # 检查 route.rules 数组数量是否大于等于2
    local rules_count=$(jq '.route.rules | length' "$config_file" 2>/dev/null)
    # 如果jq命令失败或rules为空或小于2，则认为没有足够节点配置
    if [ -z "$rules_count" ] || [ "$rules_count" -lt 2 ]; then
        return 1
    fi
    # 有2个及以上路由规则，视为已有节点配置
    return 0
}

get_public_ipv4() {
    ip -4 addr show | awk '/inet / {ip = $2; sub(/\/.*/, "", ip); if (ip !~ /^127\./ && ip !~ /^10\./ && ip !~ /^192\.168\./ && ip !~ /^169\.254\./ && ip !~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./) print ip}'
}

# 获取已配置的IP列表
get_configured_ips() {
    local config_file="/etc/sing-box/config.json"
    
    if [ ! -f "$config_file" ]; then
        echo ""
        return
    fi
    
    jq -r '.outbounds[] | .inet4_bind_address' "$config_file" | sort | uniq
}

print_node_info() {
    local ip=$1
    local socks_port=$2
    local vless_port=$3
    local username=$4
    local password=$5
    local uuid=$6
    
    echo -e " IP: \033[32m$ip\033[0m"
    echo -e " Socks5 端口: \033[32m$socks_port\033[0m 用户名: \033[32m$username\033[0m 密码: \033[32m$password\033[0m"
    echo -e " VLESS 端口: \033[32m$vless_port\033[0m UUID: \033[32m$uuid\033[0m"
    # 构建vless链接，使用IP作为备注
    local vless_link="vless://$uuid@$ip:$vless_port?security=none&type=tcp#$ip"
    # 保存节点信息到文件
    echo "$ip:$socks_port:$username:$password————$vless_link" >> "$OUTPUT_FILE"
    echo "节点信息已保存到 $OUTPUT_FILE"
}

# 导出所有节点配置
export_all_nodes() {
    local config_file="/etc/sing-box/config.json"
    
    if [ ! -f "$config_file" ]; then
        echo "Xray配置文件不存在，无法导出节点信息。"
        return 1
    fi
    
    # 初始化输出文件
    init_output_file
    
    echo "正在导出所有节点配置到 $OUTPUT_FILE..."
    
    # 获取所有Socks5节点
    local socks_nodes=$(jq -r '.inbounds[] | select(.type == "socks") | {port: .listen_port, tag: .tag}' "$config_file")
    if [ -z "$socks_nodes" ]; then
        echo "未找到任何节点配置。"
        return 1
    fi
    # 遍历所有Socks5节点，查找对应的信息
    for row in $(jq -r '.inbounds[] | select(.type == "socks") | @base64' "$config_file"); do
        inbound=$(echo $row | base64 --decode)
        local port=$(echo "$inbound" | jq -r '.listen_port')
        local tag=$(echo "$inbound" | jq -r '.tag')
        # 查找对应的outbound以获取IP
        local outbound_tag="out-$port"
        local ip=$(jq -r --arg tag "$outbound_tag" '.outbounds[] | select(.tag == $tag) | .inet4_bind_address' "$config_file")
        # 获取Socks5的用户名和密码
        local username=$(echo "$inbound" | jq -r '.users[0].username')
        local password=$(echo "$inbound" | jq -r '.users[0].password')
        # 查找相应的VLESS节点
        local vless_port=$((port + 1))
        local vless_tag="in-$vless_port"
        # 获取VLESS的UUID
        local uuid=$(jq -r --arg tag "$vless_tag" '.inbounds[] | select(.tag == $tag) | .users[0].uuid' "$config_file")
        if [ -n "$uuid" ]; then
            # 构建vless链接，使用IP作为备注
            local vless_link="vless://$uuid@$ip:$vless_port?security=none&type=tcp#$ip"
            # 输出节点信息
            echo "$ip:$port:$username:$password————$vless_link" >> "$OUTPUT_FILE"
            echo -e "已导出节点: \033[32m$ip\033[0m Socks5端口:\033[32m$port\033[0m VLESS端口:\033[32m$vless_port\033[0m"
        fi
    done
    
    echo "所有节点导出完成，信息已保存到 $OUTPUT_FILE"
    return 0
}

# 查找配置中未使用的端口号
find_next_unused_port() {
    local config_file="/etc/sing-box/config.json"
    
    if [ ! -f "$config_file" ]; then
        echo "10001" # 如果配置文件不存在，从10001开始
        return
    fi
    
    # 获取所有已使用的端口
    local used_ports=$(jq -r '.inbounds[].port' "$config_file" | sort -n)
    
    if [ -z "$used_ports" ]; then
        echo "10001" # 如果没有已使用的端口，从10001开始
        return
    fi
    
    # 获取最大的端口号并加1
    local max_port=$(echo "$used_ports" | tail -1)
    local next_port=$((max_port + 1))
    
    # 确保端口号是奇数（用于socks5）
    if [ $((next_port % 2)) -eq 0 ]; then
        next_port=$((next_port + 1))
    fi
    
    echo "$next_port"
}

# 添加新节点（只添加未配置的IP）
add_new_nodes() {
    # 获取当前系统的所有公网IP
    public_ips=($(get_public_ipv4))
    
    if [[ ${#public_ips[@]} -eq 0 ]]; then
        echo "未找到公网IP地址，退出..."
        return 1
    fi
    
    # 获取已经配置的IP列表
    configured_ips=($(get_configured_ips))
    
    # 初始化新IP列表
    new_ips=()
    
    # 比对IP，找出未配置的IP
    for ip in "${public_ips[@]}"; do
        is_configured=false
        for configured_ip in "${configured_ips[@]}"; do
            if [[ "$ip" == "$configured_ip" ]]; then
                is_configured=true
                break
            fi
        done
        
        if ! $is_configured; then
            new_ips+=("$ip")
        fi
    done
    
    # 检查是否有新的IP需要配置
    if [[ ${#new_ips[@]} -eq 0 ]]; then
        echo "所有IP都已配置，无需添加新节点。"
        return 0
    fi
    
    echo "发现 ${#new_ips[@]} 个未配置的IP: ${new_ips[@]}"
    
    # 初始化输出文件
    init_output_file
    
    # 获取配置文件路径
    config_file="/etc/sing-box/config.json"
    
    # 如果配置文件不存在，创建基础配置
    if [ ! -f "$config_file" ]; then
        cat > $config_file <<EOF
{
  "inbounds": [],
  "outbounds": [],
  "route": {
    "rules": []
  }
}
EOF
    fi
    
    # 获取下一个可用的端口
    socks_port=$(find_next_unused_port)
    
    echo "将从端口 $socks_port 开始配置新节点"
    
    # 为每个新IP配置节点
    for ip in "${new_ips[@]}"; do
        echo "正在配置 IP: $ip"
        
        # Socks5配置 (奇数端口)
        username=$(generate_random_string)
        password=$(generate_random_string)
        
        # VLESS配置 (偶数端口)
        vless_port=$((socks_port + 1))
        uuid=$(generate_uuid)
        
        # 添加Socks5配置
        jq --argjson port "$socks_port" --arg ip "$ip" --arg username "$username" --arg password "$password" '.inbounds += [{
            "type": "socks",
            "tag": ("in-\($port)"),
            "listen": "0.0.0.0",
            "listen_port": $port,
            "users": [{
                "username": $username,
                "password": $password
            }]
        }] | .outbounds += [{
            "type": "direct",
            "tag": ("out-\($port)"),
            "inet4_bind_address": $ip
        }] | .route.rules += [{
            "inbound": ["in-\($port)"],
            "outbound": "out-\($port)"
        }]' "$config_file" > temp.json && mv temp.json "$config_file"
        # 添加VLESS配置
        jq --argjson port "$vless_port" --arg ip "$ip" --arg uuid "$uuid" '.inbounds += [{
            "type": "vless",
            "tag": ("in-\($port)"),
            "listen": "0.0.0.0",
            "listen_port": $port,
            "users": [{
                "uuid": $uuid
            }]
        }] | .outbounds += [{
            "type": "direct",
            "tag": ("out-\($port)"),
            "inet4_bind_address": $ip
        }] | .route.rules += [{
            "inbound": ["in-\($port)"],
            "outbound": "out-\($port)"
        }]' "$config_file" > temp.json && mv temp.json "$config_file"
        
        # 输出节点信息
        print_node_info "$ip" "$socks_port" "$vless_port" "$username" "$password" "$uuid"
        
        # 增加端口号，为下一个IP准备
        socks_port=$((vless_port + 1))
    done
    
    echo "新节点配置完成，共添加了 ${#new_ips[@]} 个节点"
    return 0
}

configure_xray() {
    public_ips=($(get_public_ipv4))
    
    if [[ ${#public_ips[@]} -eq 0 ]]; then
        echo "未找到额外IP地址，退出..."
        exit 1
    fi
    
    echo "找到的公网 IPv4 地址: ${public_ips[@]}"
    
    # 初始化输出文件
    init_output_file
    
    config_file="/etc/sing-box/config.json"
    
    # 创建基础配置文件
    cat > $config_file <<EOF
{
  "inbounds": [],
  "outbounds": [],
  "route": {
    "rules": []
  }
}
EOF

    # 初始端口
    socks_port=10001
    
    # 配置 inbounds 和 outbounds
    for ip in "${public_ips[@]}"; do
        echo "正在配置 IP: $ip"
        # Socks5配置 (奇数端口)
        username=$(generate_random_string)
        password=$(generate_random_string)
        # VLESS配置 (偶数端口)
        vless_port=$((socks_port + 1))
        uuid=$(generate_uuid)
        # 添加Socks5配置
        jq --argjson port "$socks_port" --arg ip "$ip" --arg username "$username" --arg password "$password" '.inbounds += [{
            "type": "socks",
            "tag": ("in-\($port)"),
            "listen": "0.0.0.0",
            "listen_port": $port,
            "users": [{
                "username": $username,
                "password": $password
            }]
        }] | .outbounds += [{
            "type": "direct",
            "tag": ("out-\($port)"),
            "inet4_bind_address": $ip
        }] | .route.rules += [{
            "inbound": ["in-\($port)"],
            "outbound": "out-\($port)"
        }]' "$config_file" > temp.json && mv temp.json "$config_file"
        # 添加VLESS配置
        jq --argjson port "$vless_port" --arg ip "$ip" --arg uuid "$uuid" '.inbounds += [{
            "type": "vless",
            "tag": ("in-\($port)"),
            "listen": "0.0.0.0",
            "listen_port": $port,
            "users": [{
                "uuid": $uuid
            }]
        }] | .outbounds += [{
            "type": "direct",
            "tag": ("out-\($port)"),
            "inet4_bind_address": $ip
        }] | .route.rules += [{
            "inbound": ["in-\($port)"],
            "outbound": "out-\($port)"
        }]' "$config_file" > temp.json && mv temp.json "$config_file"
        # 输出节点信息
        print_node_info "$ip" "$socks_port" "$vless_port" "$username" "$password" "$uuid"
        # 增加端口号，为下一个IP准备
        socks_port=$((vless_port + 1))
    done

    echo "sing-box 配置完成。"
}

modify_by_ip() {
    local modify_file="/home/xiugai.txt"
    
    if [ ! -f "$modify_file" ]; then
        echo "修改文件 $modify_file 不存在，跳过修改操作。"
        return
    fi
    
    echo "检测到修改文件，开始根据IP修改节点..."
    
    # 读取当前配置
    local config_file="/etc/sing-box/config.json"
    if [ ! -f "$config_file" ]; then
        echo "Xray配置文件不存在，请先配置Xray。"
        exit 1
    fi
    
    # 初始化输出文件
    init_output_file
    
    local modify_success=false
    
    # 逐行读取修改文件中的IP
    while IFS= read -r ip || [[ -n "$ip" ]]; do
        # 跳过空行和注释行
        [[ -z "$ip" || "$ip" =~ ^# ]] && continue
        
        echo "正在处理IP: $ip"
        
        # 查找此IP对应的出站配置
        local ip_exists=$(jq --arg ip "$ip" '.outbounds[] | select(.inet4_bind_address == $ip) | .tag' "$config_file")
        
        if [[ -z "$ip_exists" ]]; then
            echo "错误: IP $ip 在当前配置中未找到，停止脚本执行。"
            exit 1
        fi
        
        # 找到对应的入站端口和标签
        local outbound_tags=$(jq -r --arg ip "$ip" '.outbounds[] | select(.inet4_bind_address == $ip) | .tag' "$config_file")
        
        for outbound_tag in $outbound_tags; do
            local port=$(echo $outbound_tag | cut -d'-' -f2)
            local inbound_tag="in-$port"
            # 检查协议类型
            local type=$(jq -r --arg tag "$inbound_tag" '.inbounds[] | select(.tag == $tag) | .type' "$config_file")
            if [[ "$type" == "socks" ]]; then
                # 更新socks协议的用户名和密码
                local username=$(generate_random_string)
                local password=$(generate_random_string)
                jq --arg tag "$inbound_tag" --arg username "$username" --arg password "$password" '
                .inbounds[] |= if .tag == $tag then 
                    .users[0].username = $username | 
                    .users[0].password = $password 
                else . end' "$config_file" > temp.json && mv temp.json "$config_file"
                # 找到对应的vless端口
                local vless_port=$((port + 1))
                local vless_tag="in-$vless_port"
                # 确认vless端口存在
                local vless_exists=$(jq --arg tag "$vless_tag" '.inbounds[] | select(.tag == $tag) | .tag' "$config_file")
                # 如果存在，更新vless协议的UUID
                if [[ -n "$vless_exists" ]]; then
                    local uuid=$(generate_uuid)
                    jq --arg tag "$vless_tag" --arg uuid "$uuid" '
                    .inbounds[] |= if .tag == $tag then 
                        .users[0].uuid = $uuid 
                    else . end' "$config_file" > temp.json && mv temp.json "$config_file"
                    # 构建vless链接，使用IP作为备注
                    local vless_link="vless://$uuid@$ip:$vless_port?security=none&type=tcp#$ip"
                    # 保存修改后的节点信息
                    echo "$ip:$port:$username:$password————$vless_link" >> "$OUTPUT_FILE"
                    echo "已修改 IP: $ip 的Socks5(端口:$port)和VLESS(端口:$vless_port)配置"
                    modify_success=true
                else
                    echo "警告: 未找到IP $ip 对应的VLESS配置"
                fi
            fi
        done
    done < "$modify_file"
    
    if $modify_success; then
        echo "节点修改完成，信息已保存到 $OUTPUT_FILE"
    else
        echo "未进行任何修改"
    fi
}

restart_xray() {
    echo "正在重启 sing-box 服务..."
    if ! systemctl restart sing-box; then
        echo "sing-box 服务重启失败，请检查配置文件。"
        exit 1
    fi
    systemctl enable sing-box
    echo "sing-box 服务已重启。"
}

# 显示交互式菜单
show_menu() {
    echo -e "\n\033[36m==== 站群多IP节点管理菜单 ====\033[0m"
    echo -e "\033[33m1. 部署节点(首次部署)\033[0m"
    echo -e "\033[33m2. 修改节点\033[0m"
    echo -e "\033[33m3. 导出所有节点\033[0m"
    echo -e "\033[33m4. 新增节点(自动添加未配置的IP)\033[0m"
    echo -e "\033[33m0. 退出\033[0m"
    echo -e "\033[36m==========================\033[0m"
    
    read -p "请输入选项 [0-4]: " choice
    
    case $choice in
        1)
            if check_existing_nodes; then
                echo -e "\033[31m警告: 检测到已有节点配置!\033[0m"
                echo -e "\033[31m选择此选项将会清空所有现有节点并重新部署所有IP的节点\033[0m"
                echo -e "\033[31m如果您只想添加新的IP节点，请使用选项4\033[0m"
                read -p "是否确认清空所有节点并重新部署? (y/n): " confirm
                if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                    echo "已取消操作"
                    show_menu
                    return
                fi
            fi
            configure_xray
            restart_xray
            echo "节点部署完成"
            ;;
        2)
            echo "请确保 /home/xiugai.txt 文件中包含需要修改的IP地址列表，每行一个IP"
            read -p "是否继续修改? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                modify_by_ip
                restart_xray
                echo "节点修改完成"
            fi
            ;;
        3)
            export_all_nodes
            ;;
        4)
            add_new_nodes
            if [ $? -eq 0 ]; then
                restart_xray
                echo "新节点添加完成"
            fi
            ;;
        0)
            echo "退出程序"
            exit 0
            ;;
        *)
            echo "无效选项，请重新选择"
            show_menu
            ;;
    esac
}

# 主函数
main() {
    # 检查是否已有节点配置
    if check_existing_nodes; then
        echo "检测到已有节点配置，跳过依赖安装..."
        show_menu
    else
        echo "未检测到节点配置，开始安装必要依赖..."
        install_jq
        install_xray
        show_menu
    fi
}

main
