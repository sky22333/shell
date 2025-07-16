#!/bin/bash

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
                    "id": "sky22333"
                }
            ]
        },
        "streamSettings": {
            "network": "ws",
            "security": "none",
            "wsSettings": {
                "path": "/sky22333"
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
        echo -e "${yellow}正在安装 xray...${none}"
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

# 显示所有入站配置和 Vmess 链接以及对应的出站配置（出战只显示地址、端口、用户名和密码）
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

        local vmess_link="vmess://$(echo -n "{\"v\":\"2\",\"ps\":\"节点$(($i + 1))\",\"add\":\"$node_address\",\"port\":$port,\"id\":\"$id\",\"aid\":0,\"net\":\"ws\",\"path\":\"$path\",\"type\":\"none\"}" | base64 -w 0)"

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
}

# 添加新节点
add_new_nodes() {
    read -p "请输入要添加的节点数量: " num_nodes
    if ! [[ $num_nodes =~ ^[0-9]+$ ]]; then
        echo -e "${red}错误!${none} 请输入有效的数量。\n"
        return
    fi

    local max_port=$(jq '[.inbounds[].port] | max // 10000' "$config_file")
    local start_port=$((max_port+1))

    for ((i=0; i<num_nodes; i++)); do
        local new_port=$((start_port+i))
        local new_tag="inbound$new_port"
        local new_outbound_tag="outbound$new_port"
        local new_id=$(uuidgen)

        # 用户输入出站代理信息
        echo "配置第 $((i+1)) 个sk5出站 (入站端口是$new_port)"
        read -p "请输入socks5出站地址, 端口, 用户名, 密码 (按顺序以空格分隔): " outbound_addr outbound_port outbound_user outbound_pass

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
            settings: { servers: [{ address: $addr, port: $port, users: [{ user: $user, pass: $pass }] }] },
            tag: $tag
        }]' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"

        # 添加路由规则
        jq --arg inTag "$new_tag" --arg outTag "$new_outbound_tag" '
        .routing.rules += [{ type: "field", inboundTag: [$inTag], outboundTag: $outTag }]
        ' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"
    done

    echo -e "${green}已成功添加 $num_nodes 个节点。${none}"
    systemctl restart xray
    echo -e "${green}Xray 服务已重新启动。${none}"
}

# 删除特定端口号的节点
delete_node_by_port() {
    read -p "请输入要删除的vmess节点端口号: " port_to_delete
    if ! [[ $port_to_delete =~ ^[0-9]+$ ]]; then
        echo -e "${red}错误!${none} 请输入有效的端口号。\n"
        return
    fi

    local inbound_tag="inbound$port_to_delete"
    local outbound_tag="outbound$port_to_delete"

    # 删除入站配置
    jq --argjson port "$port_to_delete" 'del(.inbounds[] | select(.port == $port))' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"

    # 删除出站配置
    jq --arg tag "$outbound_tag" 'del(.outbounds[] | select(.tag == $tag))' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"

    # 删除路由规则
    jq --arg inTag "$inbound_tag" --arg outTag "$outbound_tag" 'del(.routing.rules[] | select(.inboundTag[] == $inTag and .outboundTag == $outTag))' "$config_file" > "$config_file.tmp" && mv "$config_file.tmp" "$config_file"

    echo -e "${green}已成功删除端口号为 $port_to_delete 的节点。${none}"
    systemctl restart xray
    echo -e "${green}Xray 服务已重新启动。${none}"
}

# 主菜单
main_menu() {
    while true; do
        echo -e "\n${green}sky22333-快速批量搭建二级代理脚本-管理菜单:${none}"
        echo "1. 查看所有节点"
        echo "2. 新增vmess入站sk5出站"
        echo "3. 删除节点"
        echo "4. 退出"
        read -p "请输入选项: " choice

        case $choice in
            1) show_inbound_configs ;;
            2) add_new_nodes ;;
            3) delete_node_by_port ;;
            4) break ;;
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
