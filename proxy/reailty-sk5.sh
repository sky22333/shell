#!/bin/bash

# 生成随机UUID
generate_uuid() {
    sing-box generate uuid
}

# 生成Reality密钥对
generate_reality_keypair() {
    sing-box generate reality-keypair
}

# 生成随机短ID
generate_short_id() {
    sing-box generate rand 8 --hex
}

# 获取服务器公网IP
get_local_ip() {
    local ip=$(curl -s http://ipinfo.io/ip)
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$ip"
    else
        echo "无法自动获取公网IP地址，请手动输入。"
        read -p "请输入您的公网IP地址: " manual_ip
        if [[ $manual_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$manual_ip"
        else
            echo "输入的IP地址格式不正确，请重新运行脚本并输入有效的公网IP地址。"
            exit 1
        fi
    fi
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

install_singbox() {
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



# 从txt文件读取socks代理配置
get_socks_from_file() {
    local socks_file="/home/socks.txt"
    
    if [ ! -f "$socks_file" ]; then
        echo "Socks配置文件 $socks_file 不存在，请创建该文件并添加socks代理信息。"
        echo "格式: IP:端口:用户名:密码，每行一个"
        return 1
    fi
    
    # 读取文件中的socks配置，跳过空行和注释行
    grep -v '^#' "$socks_file" | grep -v '^$' | tr -d '\r'
}

# 获取已配置的socks代理列表
get_configured_socks() {
    local config_file="/etc/sing-box/config.json"
    
    if [ ! -f "$config_file" ]; then
        echo ""
        return
    fi
    
    jq -r '.outbounds[] | select(.type == "socks") | "\(.server):\(.server_port)"' "$config_file" | sort | uniq
}

print_node_info() {
    local socks_ip=$1
    local vless_port=$2
    local uuid=$3
    local public_key=$4
    local short_id=$5
    local socks_info=$6
    
    # 获取服务器公网IP
    local server_ip=$(get_local_ip)
    
    echo -e " 服务器IP: \033[32m$server_ip\033[0m"
    echo -e " VLESS 端口: \033[32m$vless_port\033[0m UUID: \033[32m$uuid\033[0m"
    echo -e " 出站Socks: \033[32m$socks_info\033[0m"
    # 构建vless+reality+grpc链接，使用服务器公网IP作为监听地址，socks IP作为备注
    local vless_link="vless://$uuid@$server_ip:$vless_port?encryption=none&flow=&security=reality&sni=www.tesla.com&fp=chrome&pbk=$public_key&sid=$short_id&type=grpc&serviceName=misakacloud&mode=gun#$socks_ip"
    # 保存节点信息到文件，每行一个VLESS链接
    echo "$vless_link" >> "$OUTPUT_FILE"
    echo "节点信息已保存到 $OUTPUT_FILE"
}

# 导出所有节点配置
export_all_nodes() {
    local config_file="/etc/sing-box/config.json"
    
    if [ ! -f "$config_file" ]; then
        echo "sing-box配置文件不存在，无法导出节点信息。"
        return 1
    fi
    
    # 初始化输出文件
    init_output_file
    
    echo "正在导出所有节点配置到 $OUTPUT_FILE..."
    
    # 获取所有VLESS节点
    local vless_nodes=$(jq -r '.inbounds[] | select(.type == "vless") | {port: .listen_port, tag: .tag}' "$config_file")
    if [ -z "$vless_nodes" ]; then
        echo "未找到任何节点配置。"
        return 1
    fi
    
    # 遍历所有VLESS节点，查找对应的信息
    for row in $(jq -r '.inbounds[] | select(.type == "vless") | @base64' "$config_file"); do
        inbound=$(echo $row | base64 --decode)
        local port=$(echo "$inbound" | jq -r '.listen_port')
        local tag=$(echo "$inbound" | jq -r '.tag')
        # 查找对应的outbound获取socks信息
        local outbound_tag="out-$port"
        local socks_outbound=$(jq -r --arg tag "$outbound_tag" '.outbounds[] | select(.tag == $tag)' "$config_file")
        local socks_server=$(echo "$socks_outbound" | jq -r '.server')
        local socks_port=$(echo "$socks_outbound" | jq -r '.server_port')
        local socks_user=$(echo "$socks_outbound" | jq -r '.username')
        local socks_pass=$(echo "$socks_outbound" | jq -r '.password')
        local socks_info="$socks_server:$socks_port:$socks_user:$socks_pass"
        
        # 获取VLESS的配置信息
        local uuid=$(echo "$inbound" | jq -r '.users[0].uuid')
        local public_key=$(echo "$inbound" | jq -r '.tls.reality.public_key // empty')
        local short_id=$(echo "$inbound" | jq -r '.tls.reality.short_id[0] // empty')
        
        if [ -n "$uuid" ]; then
            # 获取服务器公网IP
            local server_ip=$(get_local_ip)
            # 构建vless+reality+grpc链接，使用服务器公网IP作为监听地址，socks IP作为备注
            local vless_link="vless://$uuid@$server_ip:$port?encryption=none&flow=&security=reality&sni=www.tesla.com&fp=chrome&pbk=$public_key&sid=$short_id&type=grpc&serviceName=misakacloud&mode=gun#$socks_server"
            # 输出节点信息，每行一个VLESS链接
            echo "$vless_link" >> "$OUTPUT_FILE"
            echo -e "已导出节点: \033[32m$server_ip\033[0m VLESS端口:\033[32m$port\033[0m Socks:\033[32m$socks_info\033[0m"
        fi
    done
    
    echo "所有节点导出完成，信息已保存到 $OUTPUT_FILE"
    return 0
}

# 查找配置中未使用的端口号
find_next_unused_port() {
    local config_file="/etc/sing-box/config.json"
    
    if [ ! -f "$config_file" ]; then
        echo "10000" # 如果配置文件不存在，从10000开始
        return
    fi
    
    # 获取所有已使用的端口
    local used_ports=$(jq -r '.inbounds[].listen_port' "$config_file" | sort -n)
    
    if [ -z "$used_ports" ]; then
        echo "10000" # 如果没有已使用的端口，从10000开始
        return
    fi
    
    # 获取最大的端口号并加1
    local max_port=$(echo "$used_ports" | tail -1)
    local next_port=$((max_port + 1))
    
    echo "$next_port"
}

# 添加新节点（只添加未配置的socks代理）
add_new_nodes() {
    # 从txt文件获取socks配置列表
    local file_socks
    file_socks=$(get_socks_from_file)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    socks_configs=($file_socks)
    
    if [[ ${#socks_configs[@]} -eq 0 ]]; then
        echo "Socks配置文件中未找到有效的配置，退出..."
        return 1
    fi
    
    # 获取已经配置的socks代理列表
    configured_socks=($(get_configured_socks))
    
    # 初始化新socks列表
    new_socks=()
    
    # 比对socks配置，找出未配置的
    for socks_config in "${socks_configs[@]}"; do
        IFS=':' read -r socks_ip socks_port socks_user socks_pass <<< "$socks_config"
        socks_key="$socks_ip:$socks_port"
        
        is_configured=false
        for configured_socks in "${configured_socks[@]}"; do
            if [[ "$socks_key" == "$configured_socks" ]]; then
                is_configured=true
                break
            fi
        done
        
        if ! $is_configured; then
            new_socks+=("$socks_config")
        fi
    done
    
    # 检查是否有新的socks需要配置
    if [[ ${#new_socks[@]} -eq 0 ]]; then
        echo "所有Socks代理都已配置，无需添加新节点。"
        return 0
    fi
    
    echo "发现 ${#new_socks[@]} 个未配置的Socks代理"
    
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
    vless_port=$(find_next_unused_port)
    
    echo "将从端口 $vless_port 开始配置新节点"
    
    # 为每个新socks配置节点
    for socks_config in "${new_socks[@]}"; do
        IFS=':' read -r socks_ip socks_port socks_user socks_pass <<< "$socks_config"
        echo "正在配置 Socks代理: $socks_config"
        
        # VLESS配置
        uuid=$(generate_uuid)
        # 生成Reality密钥对
        keypair=$(generate_reality_keypair)
        private_key=$(echo "$keypair" | grep "PrivateKey:" | awk '{print $2}')
        public_key=$(echo "$keypair" | grep "PublicKey:" | awk '{print $2}')
        short_id=$(generate_short_id)
        
        # 添加VLESS入站和Socks出站配置
        jq --argjson port "$vless_port" --arg uuid "$uuid" --arg private_key "$private_key" --arg short_id "$short_id" \
           --arg socks_ip "$socks_ip" --argjson socks_port "$socks_port" --arg socks_user "$socks_user" --arg socks_pass "$socks_pass" \
           '.inbounds += [{
            "type": "vless",
            "tag": ("in-\($port)"),
            "listen": "::",
            "listen_port": $port,
            "users": [{
                "uuid": $uuid
            }],
            "tls": {
                "enabled": true,
                "server_name": "www.tesla.com",
                "reality": {
                    "enabled": true,
                    "handshake": {
                        "server": "www.tesla.com",
                        "server_port": 443
                    },
                    "private_key": $private_key,
                    "short_id": [$short_id]
                }
            },
            "transport": {
                "type": "grpc",
                "service_name": "misakacloud"
            }
        }] | .outbounds += [{
            "type": "socks",
            "tag": ("out-\($port)"),
            "server": $socks_ip,
            "server_port": $socks_port,
            "username": $socks_user,
            "password": $socks_pass,
            "version": "5"
        }] | .route.rules += [{
            "inbound": ["in-\($port)"],
            "outbound": "out-\($port)"
        }]' "$config_file" > temp.json && mv temp.json "$config_file"
        
        # 输出节点信息
        print_node_info "$socks_ip" "$vless_port" "$uuid" "$public_key" "$short_id" "$socks_config"
        
        # 增加端口号，为下一个socks准备
        vless_port=$((vless_port + 1))
    done
    
    echo "新节点配置完成，共添加了 ${#new_socks[@]} 个节点"
    return 0
}

configure_xray() {
    # 从txt文件获取socks配置列表
    local file_socks
    file_socks=$(get_socks_from_file)
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    socks_configs=($file_socks)
    
    if [[ ${#socks_configs[@]} -eq 0 ]]; then
        echo "Socks配置文件中未找到有效的配置，退出..."
        exit 1
    fi
    
    echo "从文件读取的 Socks 配置数量: ${#socks_configs[@]}"
    
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
    vless_port=10000
    
    # 配置 inbounds 和 outbounds
    for socks_config in "${socks_configs[@]}"; do
        IFS=':' read -r socks_ip socks_port socks_user socks_pass <<< "$socks_config"
        echo "正在配置 Socks代理: $socks_config"
        
        # VLESS配置
        uuid=$(generate_uuid)
        # 生成Reality密钥对
        keypair=$(generate_reality_keypair)
        private_key=$(echo "$keypair" | grep "PrivateKey:" | awk '{print $2}')
        public_key=$(echo "$keypair" | grep "PublicKey:" | awk '{print $2}')
        short_id=$(generate_short_id)
        
        # 添加VLESS入站和Socks出站配置
        jq --argjson port "$vless_port" --arg uuid "$uuid" --arg private_key "$private_key" --arg short_id "$short_id" \
           --arg socks_ip "$socks_ip" --argjson socks_port "$socks_port" --arg socks_user "$socks_user" --arg socks_pass "$socks_pass" \
           '.inbounds += [{
            "type": "vless",
            "tag": ("in-\($port)"),
            "listen": "::",
            "listen_port": $port,
            "users": [{
                "uuid": $uuid
            }],
            "tls": {
                "enabled": true,
                "server_name": "www.tesla.com",
                "reality": {
                    "enabled": true,
                    "handshake": {
                        "server": "www.tesla.com",
                        "server_port": 443
                    },
                    "private_key": $private_key,
                    "short_id": [$short_id]
                }
            },
            "transport": {
                "type": "grpc",
                "service_name": "misakacloud"
            }
        }] | .outbounds += [{
            "type": "socks",
            "tag": ("out-\($port)"),
            "server": $socks_ip,
            "server_port": $socks_port,
            "username": $socks_user,
            "password": $socks_pass,
            "version": "5"
        }] | .route.rules += [{
            "inbound": ["in-\($port)"],
            "outbound": "out-\($port)"
        }]' "$config_file" > temp.json && mv temp.json "$config_file"
        
        # 输出节点信息
        print_node_info "$socks_ip" "$vless_port" "$uuid" "$public_key" "$short_id" "$socks_config"
        
        # 增加端口号，为下一个socks准备
        vless_port=$((vless_port + 1))
    done

    echo "sing-box 配置完成。"
}

modify_by_ip() {
    local modify_file="/home/xiugai.txt"
    
    if [ ! -f "$modify_file" ]; then
        echo "修改文件 $modify_file 不存在，跳过修改操作。"
        return
    fi
    
    echo "检测到修改文件，开始根据Socks代理修改节点..."
    echo "文件格式应为: IP:端口:用户名:密码，每行一个"
    
    # 读取当前配置
    local config_file="/etc/sing-box/config.json"
    if [ ! -f "$config_file" ]; then
        echo "sing-box配置文件不存在，请先配置sing-box。"
        exit 1
    fi
    
    # 初始化输出文件
    init_output_file
    
    local modify_success=false
    
    # 逐行读取修改文件中的socks配置
    while IFS= read -r socks_config || [[ -n "$socks_config" ]]; do
        # 跳过空行和注释行
        [[ -z "$socks_config" || "$socks_config" =~ ^# ]] && continue
        
        IFS=':' read -r socks_ip socks_port socks_user socks_pass <<< "$socks_config"
        echo "正在处理Socks代理: $socks_config"
        
        # 查找此socks代理对应的出站配置
        local socks_exists=$(jq --arg ip "$socks_ip" --argjson port "$socks_port" '.outbounds[] | select(.server == $ip and .server_port == $port) | .tag' "$config_file")
        
        if [[ -z "$socks_exists" ]]; then
            echo "错误: Socks代理 $socks_config 在当前配置中未找到，停止脚本执行。"
            exit 1
        fi
        
        # 找到对应的入站端口和标签
        local outbound_tags=$(jq -r --arg ip "$socks_ip" --argjson port "$socks_port" '.outbounds[] | select(.server == $ip and .server_port == $port) | .tag' "$config_file")
        
        for outbound_tag in $outbound_tags; do
            local vless_port=$(echo $outbound_tag | cut -d'-' -f2)
            local inbound_tag="in-$vless_port"
            # 检查协议类型
            local type=$(jq -r --arg tag "$inbound_tag" '.inbounds[] | select(.tag == $tag) | .type' "$config_file")
            if [[ "$type" == "vless" ]]; then
                # 更新vless协议的UUID和Reality配置
                local uuid=$(generate_uuid)
                # 生成新的Reality密钥对
                keypair=$(generate_reality_keypair)
                private_key=$(echo "$keypair" | grep "PrivateKey:" | awk '{print $2}')
                public_key=$(echo "$keypair" | grep "PublicKey:" | awk '{print $2}')
                short_id=$(generate_short_id)
                
                # 更新入站配置
                jq --arg tag "$inbound_tag" --arg uuid "$uuid" --arg private_key "$private_key" --arg short_id "$short_id" '
                .inbounds[] |= if .tag == $tag then 
                    .users[0].uuid = $uuid |
                    .tls.reality.private_key = $private_key |
                    .tls.reality.short_id = [$short_id]
                else . end' "$config_file" > temp.json && mv temp.json "$config_file"
                
                # 更新出站socks配置
                jq --arg tag "$outbound_tag" --arg socks_user "$socks_user" --arg socks_pass "$socks_pass" '
                .outbounds[] |= if .tag == $tag then 
                    .username = $socks_user |
                    .password = $socks_pass
                else . end' "$config_file" > temp.json && mv temp.json "$config_file"
                
                # 获取服务器公网IP
                local server_ip=$(get_local_ip)
                # 构建vless+reality+grpc链接，使用服务器公网IP作为监听地址，socks IP作为备注
                local vless_link="vless://$uuid@$server_ip:$vless_port?encryption=none&flow=&security=reality&sni=www.tesla.com&fp=chrome&pbk=$public_key&sid=$short_id&type=grpc&serviceName=misakacloud&mode=gun#$socks_ip"
                # 保存修改后的节点信息，每行一个VLESS链接
                echo "$vless_link" >> "$OUTPUT_FILE"
                echo "已修改 Socks代理: $socks_config 的VLESS(端口:$vless_port)配置"
                modify_success=true
            fi
        done
    done < "$modify_file"
    
    if $modify_success; then
        echo "节点修改完成，信息已保存到 $OUTPUT_FILE"
    else
        echo "未进行任何修改"
    fi
}

restart_singbox() {
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
    echo -e "\n\033[36m==== reailty入站socks出站脚本 ====\033[0m"
    echo -e "\033[33m1. 部署节点(首次部署)\033[0m"
    echo -e "\033[33m2. 修改节点\033[0m"
    echo -e "\033[33m3. 导出所有节点\033[0m"
    echo -e "\033[33m4. 新增节点\033[0m"
    echo -e "\033[33m0. 退出\033[0m"
    echo -e "\033[36m==========================\033[0m"
    
    read -p "请输入选项 [0-4]: " choice
    
    case $choice in
        1)
            echo "请确保 /home/socks.txt 文件中包含需要部署的Socks代理配置"
            echo "格式: IP:端口:用户名:密码，每行一个"
            if check_existing_nodes; then
                echo -e "\033[31m警告: 检测到已有节点配置!\033[0m"
                echo -e "\033[31m选择此选项将会清空所有现有节点并重新部署所有Socks代理的节点\033[0m"
                echo -e "\033[31m如果您只想添加新的Socks代理节点，请使用选项4\033[0m"
                read -p "是否确认清空所有节点并重新部署? (y/n): " confirm
                if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                    echo "已取消操作"
                    show_menu
                    return
                fi
            else
                read -p "是否继续部署节点? (y/n): " confirm
                if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                    echo "已取消操作"
                    show_menu
                    return
                fi
            fi
            configure_xray
            restart_singbox
            echo "节点部署完成"
            ;;
        2)
            echo "请确保 /home/xiugai.txt 文件中包含需要修改的Socks代理配置"
            echo "格式: IP:端口:用户名:密码，每行一个（根据IP地址匹配）"
            read -p "是否继续修改? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                modify_by_ip
                restart_singbox
                echo "节点修改完成"
            fi
            ;;
        3)
            export_all_nodes
            ;;
        4)
            echo "请确保 /home/socks.txt 文件中包含需要添加的Socks代理配置"
            echo "格式: IP:端口:用户名:密码，每行一个"
            read -p "是否继续添加新节点? (y/n): " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                add_new_nodes
                if [ $? -eq 0 ]; then
                    restart_singbox
                    echo "新节点添加完成"
                fi
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
        install_singbox
        show_menu
    fi
}

main
