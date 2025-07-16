#!/bin/bash
# 批量搭建vmess+ws入站到sk5出站代理
# 读取sk5文件实现批量导入出站
# 作者sky22333

red='\e[31m'
yellow='\e[33m'
green='\e[32m'
none='\e[0m'
config_file="/usr/local/etc/xray/config.json"
default_config='
{
  "inbounds": [
    {
        "listen": "127.0.0.1",
        "port": 9999,
        "protocol": "vmess",
        "settings": {
            "clients": [
                {
                    "id": "wss"
                }
            ]
        },
        "streamSettings": {
            "network": "ws",
            "security": "none",
            "wsSettings": {
                "path": "/wss"
            }
        },
        "tag": "inbound0"
    }
  ],
  "outbounds": [
    {
        "protocol": "socks",
        "settings": {
            "servers": [
                {
                    "address": "127.0.0.2",
                    "port": 2222,
                    "users": [
                        {
                            "user": "admin123",
                            "pass": "admin333"
                        }
                    ]
                }
            ]
        },
        "tag": "outbound0"
    }
  ],
  "routing": {
    "rules": [
    {
        "type": "field",
        "inboundTag": ["inbound0"],
        "outboundTag": "outbound0"
    }
    ]
  }
}
'

# 检查并安装curl
check_and_install_curl() {
    if ! type curl &>/dev/null; then
        echo -e "${yellow}正在安装curl...${none}"
        apt update && apt install -yq curl
    fi
}

# 检查并安装jq
check_and_install_jq() {
    if ! type jq &>/dev/null; then
        echo -e "${yellow}正在安装jq...${none}"
        apt update && apt install -yq jq
    fi
}

# 检查并安装uuid-runtime
check_and_install_uuid_runtime() {
    if ! type uuidgen &>/dev/null; then
        echo -e "${yellow}正在安装 uuid-runtime...${none}"
        apt update && apt install -yq uuid-runtime
    fi
}

# 检查并安装xray
check_and_install_xray() {
    if ! type xray &>/dev/null; then
        echo -e "${yellow}正在安装 xray...正在启用BBR...${none}"
        sudo ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
        bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install --version v1.8.4
    fi
}

# 检查是否已存在入站配置
check_existing_inbound_config() {
    if grep -q '"tag":' "$config_file"; then
        return 0  # 已存在入站配置
    else
        return 1  # 不存在入站配置
    fi
}

# 创建默认配置文件
create_default_config() {
    if ! check_existing_inbound_config; then
        echo "$default_config" > "$config_file"
        echo -e "${green}已创建默认配置文件。${none}"
    else
        echo -e "${yellow}入站配置已存在，跳过创建默认配置文件。${none}"
    fi
}

# 获取本机公网 IP
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

# 生成带时间戳的vmess文件名(精确到秒)
get_vmess_filename() {
    local timestamp=$(date +"%Y%m%d-%H点%M分%S秒")
    echo "/home/${timestamp}-vmess.txt"
}

# 保存多个VMess节点到文件
save_multiple_vmess_links() {
    local local_ip=$1
    shift
    local vmess_file=$(get_vmess_filename)
    
    # 清空或创建文件
    > "$vmess_file"
    
    # 处理所有传入的节点信息
    while [[ $# -gt 0 ]]; do
        local port=$1
        local id=$2
        local path=$3
        local index=$4
        shift 4
        # 获取对应的出站 SOCKS5 的 IP 地址
        local sk5_ip=$(jq -r ".outbounds | map(select(.tag == \"outbound${port}\")) | .[0].settings.servers[0].address" "$config_file")
        if [[ -z "$sk5_ip" ]]; then
            sk5_ip="未知IP" # 如果未找到对应的IP，设置为默认值
        fi
        
        # 生成VMess链接
        local vmess_link="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$sk5_ip\",\"add\":\"$local_ip\",\"port\":$port,\"id\":\"$id\",\"aid\":0,\"net\":\"ws\",\"path\":\"$path\",\"type\":\"none\"}" | base64 -w 0)"
        
        # 写入文件
        echo "$vmess_link" >> "$vmess_file"
    done
    
    echo -e "${green}已将操作的所有节点保存至 $vmess_file${none}"
}

# 保存多个VMess节点到文件（带自定义PS字段）
save_multiple_vmess_links_with_ps() {
    local local_ip=$1
    shift
    local vmess_file=$(get_vmess_filename)
    
    # 清空或创建文件
    > "$vmess_file"
    
    # 处理所有传入的节点信息
    while [[ $# -gt 0 ]]; do
        local port=$1
        local id=$2
        local path=$3
        local index=$4
        local sk5_ip=$5  # 额外参数用于PS字段
        shift 5
        
        # 生成VMess链接，使用自定义PS字段
        local vmess_link="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$sk5_ip\",\"add\":\"$local_ip\",\"port\":$port,\"id\":\"$id\",\"aid\":0,\"net\":\"ws\",\"path\":\"$path\",\"type\":\"none\"}" | base64 -w 0)"
        
        # 写入文件
        echo "$vmess_link" >> "$vmess_file"
    done
    
    echo -e "${green}已将操作的所有节点保存至 $vmess_file${none}"
}

# 保存所有VMess节点到文件
save_all_vmess_links() {
    local local_ip=$(get_local_ip)  # 获取本机IP
    local vmess_file=$(get_vmess_filename)
    
    # 清空或创建文件
    > "$vmess_file"
    
    local config=$(jq '.inbounds | map(select(.port != 9999))' "$config_file")
    local length=$(jq '. | length' <<< "$config")
    
    for ((i = 0; i < length; i++)); do
        local port=$(jq -r ".[$i].port" <<< "$config")
        local id=$(jq -r ".[$i].settings.clients[0].id" <<< "$config")
        local path=$(jq -r ".[$i].streamSettings.wsSettings.path" <<< "$config")
        
		# 获取对应的出站 SOCKS5 的 IP 地址
        local sk5_ip=$(jq -r ".outbounds | map(select(.tag == \"outbound${port}\")) | .[0].settings.servers[0].address" "$config_file")
        if [[ -z "$sk5_ip" ]]; then
            sk5_ip="未知IP" # 如果未找到对应的IP，设置为默认值
        fi
        # 生成VMess链接
        local vmess_link="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$sk5_ip\",\"add\":\"$local_ip\",\"port\":$port,\"id\":\"$id\",\"aid\":0,\"net\":\"ws\",\"path\":\"$path\",\"type\":\"none\"}" | base64 -w 0)"
        
        # 写入文件
        echo "$vmess_link" >> "$vmess_file"
    done
    
    echo -e "${green}已将全部VMess节点保存至 $vmess_file${none}"
}

# 显示所有入站配置和 Vmess 链接以及对应的出站配置
show_inbound_configs() {
    local local_ip=$(get_local_ip)  # 获取本机IP

    local config=$(jq '.inbounds | map(select(.port != 9999))' "$config_file")
    local outbounds=$(jq '.outbounds' "$config_file")
    echo -e "${green}入站节点配置:${none}"

    local length=$(jq '. | length' <<< "$config")
    for ((i = 0; i < length; i++)); do
        local port=$(jq -r ".[$i].port" <<< "$config")
        local id=$(jq -r ".[$i].settings.clients[0].id" <<< "$config")
        local path=$(jq -r ".[$i].streamSettings.wsSettings.path" <<< "$config")

        # 将节点地址设置为本机IP
        local node_address="$local_ip"

		# 获取sk5代理IP
        local sk5_ip=$(jq -r ".outbounds | map(select(.tag == \"outbound${port}\")) | .[0].settings.servers[0].address" "$config_file")
        if [[ -z "$sk5_ip" ]]; then
            sk5_ip="未知IP" # 如果未找到对应的IP，设置为默认值
        fi
        local vmess_link="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"$sk5_ip\",\"add\":\"$node_address\",\"port\":$port,\"id\":\"$id\",\"aid\":0,\"net\":\"ws\",\"path\":\"$path\",\"type\":\"none\"}" | base64 -w 0)"

        echo -e "${yellow}节点: $(($i + 1))${none} - 端口: ${port}, Vmess 链接: ${vmess_link}"
        
        # 构造出站配置的标签
        local outbound_tag="outbound$port"

        # 根据构造的标签查找对应的出站配置
        local outbound_config=$(jq --arg tag "$outbound_tag" '.[] | select(.tag == $tag) | .settings.servers[] | {address, port, user: .users[0].user, pass: .users[0].pass}' <<< "$outbounds")
        
        if [[ ! -z $outbound_config ]]; then
            echo -e "${green}出站配置:${none} 地址: $(jq -r '.address' <<< "$outbound_config"), 端口: $(jq -r '.port' <<< "$outbound_config"), 用户名: $(jq -r '.user' <<< "$outbound_config"), 密码: $(jq -r '.pass' <<< "$outbound_config")"
        else
            echo -e "${red}未找到对应的出站配置。${none}"
        fi
    done
    
    # 保存所有VMess链接到文件
    save_all_vmess_links
}

# 添加新节点
add_new_nodes() {
    local sk5_file="/home/sk5.txt"
    
    # 检查sk5.txt文件是否存在
    if [ ! -f "$sk5_file" ]; then
        echo -e "${red}错误!${none} $sk5_file 文件不存在。"
        return
    fi
    
    # 读取sk5.txt文件中的代理信息
    local sk5_proxies=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 忽略空行
        if [[ -z "$line" ]]; then
            continue
        fi
        sk5_proxies+=("$line")
    done < "$sk5_file"
    
    # 检查是否读取到代理
    local proxy_count=${#sk5_proxies[@]}
    if [ $proxy_count -eq 0 ]; then
        echo -e "${red}错误!${none} 未在 $sk5_file 中找到有效的代理配置。"
        return
    fi
    
    echo -e "${green}从 $sk5_file 读取到 $proxy_count 个代理配置。${none}"
    read -p "是否要导入全部配置？(y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        read -p "请输入要导入的代理数量 (最大 $proxy_count): " num_to_import
        if ! [[ $num_to_import =~ ^[0-9]+$ ]] || [ $num_to_import -le 0 ] || [ $num_to_import -gt $proxy_count ]; then
            echo -e "${red}错误!${none} 输入数量无效。"
            return
        fi
    else
        num_to_import=$proxy_count
    fi
    
    local max_port=$(jq '[.inbounds[].port] | max // 10000' "$config_file")
    local start_port=$((max_port+1))
    local local_ip=$(get_local_ip)
    local nodes_to_save=()
    
    for ((i=0; i<num_to_import; i++)); do
        local new_port=$((start_port+i))
        local new_tag="inbound$new_port"
        local new_outbound_tag="outbound$new_port"
        local new_id=$(uuidgen)
        
        # 解析代理信息 (格式: IP:端口:用户名:密码)
        IFS=':' read -r outbound_addr outbound_port outbound_user outbound_pass <<< "${sk5_proxies[$i]}"
        
        if [[ -z "$outbound_addr" || -z "$outbound_port" || -z "$outbound_user" || -z "$outbound_pass" ]]; then
            echo -e "${red}警告:${none} 代理 #$((i+1)) 格式无效，终止脚本运行: ${sk5_proxies[$i]}"
            exit 1
        fi
        
        echo -e "${yellow}配置入站端口 $new_port 连接到代理 $outbound_addr:$outbound_port${none}"
        
        # 添加入站配置（入站地址设置为 "0.0.0.0"）
        jq --argjson port "$new_port" --arg id "$new_id" --arg tag "$new_tag" '
        .inbounds += [{
            listen: "0.0.0.0",
            port: $port,
            protocol: "vmess",
            settings: { clients: [{ id: $id }] },
            streamSettings: { network: "ws", security: "none", wsSettings: { path: "/websocket" } },
            tag: $tag
        }]' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"

        # 添加出站配置
        jq --arg tag "$new_outbound_tag" --arg addr "$outbound_addr" --argjson port "$outbound_port" --arg user "$outbound_user" --arg pass "$outbound_pass" '
        .outbounds += [{
            protocol: "socks",
            settings: { servers: [{ address: $addr, port: $port | tonumber, users: [{ user: $user, pass: $pass }] }] },
            tag: $tag
        }]' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"

        # 添加路由规则
        jq --arg inTag "$new_tag" --arg outTag "$new_outbound_tag" '
        .routing.rules += [{ type: "field", inboundTag: [$inTag], outboundTag: $outTag }]
        ' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
        
        # 保存节点信息以便后续生成VMess链接
        nodes_to_save+=("$new_port" "$new_id" "/websocket" "$((i+1))")
    done

    # 保存所有新添加的节点到一个文件
    save_multiple_vmess_links "$local_ip" "${nodes_to_save[@]}"

    echo -e "${green}已成功添加 $num_to_import 个节点。${none}"
    sudo systemctl restart xray
    echo -e "${green}Xray 服务已重新启动。${none}"
}

# 根据xiugai.txt文件修改SOCKS5出站代理
modify_socks5_outbound() {
    local modify_file="/home/xiugai.txt"
    
    # 检查xiugai.txt文件是否存在
    if [ ! -f "$modify_file" ]; then
        echo -e "${red}错误!${none} $modify_file 文件不存在。"
        return
    fi
    
    # 读取xiugai.txt文件中的代理信息
    local modify_proxies=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 忽略空行
        if [[ -z "$line" ]]; then
            continue
        fi
        modify_proxies+=("$line")
    done < "$modify_file"
    
    # 检查是否读取到代理
    local proxy_count=${#modify_proxies[@]}
    if [ $proxy_count -eq 0 ]; then
        echo -e "${red}错误!${none} 未在 $modify_file 中找到有效的代理配置。"
        return
    fi
    
    echo -e "${green}从 $modify_file 读取到 $proxy_count 个代理配置。${none}"
    local local_ip=$(get_local_ip)
    local nodes_to_save=()
    
    # 处理每个要修改的代理
    for proxy in "${modify_proxies[@]}"; do
        IFS=':' read -r old_ip new_port new_user new_pass <<< "$proxy"
        
        if [[ -z "$old_ip" || -z "$new_port" || -z "$new_user" || -z "$new_pass" ]]; then
            echo -e "${red}警告:${none} 代理格式无效，终止脚本运行: $proxy"
            exit 1
        fi
        
        # 查找匹配的出站节点
        local outbound_config=$(jq --arg ip "$old_ip" '.outbounds[] | select(.protocol == "socks" and .settings.servers[0].address == $ip) | {tag: .tag, address: .settings.servers[0].address, port: .settings.servers[0].port, user: .settings.servers[0].users[0].user, pass: .settings.servers[0].users[0].pass}' "$config_file")
        
        if [[ -z "$outbound_config" ]]; then
            echo -e "${red}警告:${none} 未找到IP地址为 $old_ip 的SOCKS5出站节点，终止脚本运行"
            exit 1
        fi
        
        local tag=$(echo "$outbound_config" | jq -r '.tag')
        local old_port=$(echo "$outbound_config" | jq -r '.port')
        local old_user=$(echo "$outbound_config" | jq -r '.user')
        local old_pass=$(echo "$outbound_config" | jq -r '.pass')
        
        echo -e "${yellow}找到匹配的出站节点:${none} 标签=$tag, 旧IP=$old_ip, 旧端口=$old_port, 旧用户名=$old_user, 旧密码=$old_pass"
        echo -e "${green}将更新为:${none} 新IP=$old_ip, 新端口=$new_port, 新用户名=$new_user, 新密码=$new_pass"
        
        # 更新SOCKS5出站配置
        local temp_file=$(mktemp)
        jq --arg tag "$tag" \
           --arg ip "$old_ip" \
           --argjson port "$new_port" \
           --arg user "$new_user" \
           --arg pass "$new_pass" \
        '(.outbounds[] | select(.tag == $tag) | .settings.servers[0].address) = $ip |
         (.outbounds[] | select(.tag == $tag) | .settings.servers[0].port) = $port |
         (.outbounds[] | select(.tag == $tag) | .settings.servers[0].users[0].user) = $user |
         (.outbounds[] | select(.tag == $tag) | .settings.servers[0].users[0].pass) = $pass' \
        "$config_file" > "$temp_file"
        
        if [ $? -eq 0 ] && [ -s "$temp_file" ]; then
            mv "$temp_file" "$config_file"
            echo -e "${green}成功修改SOCKS5出站节点配置!${none}"
            
            # 查找对应的入站配置并保存节点信息
            local inbound_port=${tag//outbound/}
            local inbound_config=$(jq --argjson port "$inbound_port" '.inbounds[] | select(.port == $port)' "$config_file")
            if [[ -n "$inbound_config" ]]; then
                local id=$(echo "$inbound_config" | jq -r '.settings.clients[0].id')
                local path=$(echo "$inbound_config" | jq -r '.streamSettings.wsSettings.path')
                local index=$(jq '.inbounds | map(select(.port != 9999)) | map(.port == '$inbound_port') | index(true)' "$config_file")
                
                # 修复: 包含实际的SOCKS5 IP地址作为PS字段
                nodes_to_save+=("$inbound_port" "$id" "$path" "$((index+1))" "$old_ip")
            fi
        else
            echo -e "${red}更新配置失败!${none}"
            rm -f "$temp_file"
            continue
        fi
    done
    
    # 保存所有修改的节点到一个文件，使用新函数传递PS字段
    if [[ ${#nodes_to_save[@]} -gt 0 ]]; then
        save_multiple_vmess_links_with_ps "$local_ip" "${nodes_to_save[@]}"
    fi
    
    # 重启Xray服务使配置生效
    sudo chmod 755 /usr/local/etc/xray/config.json
    sudo systemctl restart xray
    echo -e "${green}Xray 服务已重新启动。${none}"
}

# 根据xiugai.txt文件删除节点
delete_nodes_by_ip() {
    local modify_file="/home/xiugai.txt"
    
    # 检查xiugai.txt文件是否存在
    if [ ! -f "$modify_file" ]; then
        echo -e "${red}错误!${none} $modify_file 文件不存在。"
        return
    fi
    
    # 读取xiugai.txt文件中的代理信息
    local modify_proxies=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 忽略空行
        if [[ -z "$line" ]]; then
            continue
        fi
        # 只提取IP部分
        IFS=':' read -r ip _ <<< "$line"
        modify_proxies+=("$ip")
    done < "$modify_file"
    
    # 检查是否读取到IP
    local ip_count=${#modify_proxies[@]}
    if [ $ip_count -eq 0 ]; then
        echo -e "${red}错误!${none} 未在 $modify_file 中找到有效的IP地址。"
        return
    fi
    
    echo -e "${green}从 $modify_file 读取到 $ip_count 个IP地址。${none}"
    
    # 处理每个要删除的IP
    for ip in "${modify_proxies[@]}"; do
        # 查找匹配的出站节点
        local outbound_config=$(jq --arg ip "$ip" '.outbounds[] | select(.protocol == "socks" and .settings.servers[0].address == $ip) | {tag: .tag, port: .settings.servers[0].port}' "$config_file")
        
        if [[ -z "$outbound_config" ]]; then
            echo -e "${red}警告:${none} 未找到IP地址为 $ip 的SOCKS5出站节点，终止脚本运行"
            exit 1
        fi
        
        local outbound_tag=$(echo "$outbound_config" | jq -r '.tag')
        
        # 从outbound_tag中提取端口号（假设格式为"outbound端口号"）
        local port=${outbound_tag#outbound}
        
        echo -e "${yellow}找到匹配的节点:${none} 出站标签=$outbound_tag, IP=$ip, 端口=$port"
        
        # 查找对应的入站配置
        local inbound_config=$(jq --argjson port "$port" '.inbounds[] | select(.port == $port)' "$config_file")
        
        if [[ -z "$inbound_config" ]]; then
            echo -e "${red}警告:${none} 未找到对应端口 $port 的入站配置，继续删除出站配置"
        else
            local inbound_tag=$(echo "$inbound_config" | jq -r '.tag')
            echo -e "${yellow}找到对应的入站配置:${none} 标签=$inbound_tag"
            
            # 删除入站配置
            jq --argjson port "$port" 'del(.inbounds[] | select(.port == $port))' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
            
            # 删除路由规则（使用实际的inbound_tag而不是构造的标签）
            jq --arg inTag "$inbound_tag" 'del(.routing.rules[] | select(.inboundTag[] == $inTag))' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
        fi
        
        # 删除出站配置
        jq --arg tag "$outbound_tag" 'del(.outbounds[] | select(.tag == $tag))' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
        
        echo -e "${green}已成功删除IP地址为 $ip 的节点。${none}"
    done
    
    sudo systemctl restart xray
    echo -e "${green}Xray 服务已重新启动。${none}"
}

# 主菜单
main_menu() {
    while true; do
        echo -e "\n${green}快速批量搭建二级代理脚本-管理菜单:${none}"
        echo "1. 查看所有节点"
        echo "2. 新增vmess入站sk5出站(从/home/sk5.txt文件导入)"
        echo "3. 删除节点(根据/home/xiugai.txt文件匹配)"
        echo "4. 修改SOCKS5出站节点(根据/home/xiugai.txt文件匹配)"
        echo "5. 退出"
        read -p "请输入选项: " choice

        case $choice in
            1) show_inbound_configs ;;
            2) add_new_nodes ;;
            3) delete_nodes_by_ip ;;
            4) modify_socks5_outbound ;;
            5) break ;;
            *) echo -e "${red}无效的选项，请重新选择。${none}" ;;
        esac
    done
}

# 调用主菜单函数
check_and_install_curl
check_and_install_jq
check_and_install_uuid_runtime
check_and_install_xray
create_default_config
get_local_ip
main_menu
