#!/bin/bash
# 弹性多IP搭建脚本

set -euo pipefail
shopt -s failglob

# 颜色定义
GREEN='\033[0;32m'
WHITE='\033[1;37m'
RED='\033[0;31m'
NC='\033[0m'

# 初始化计数器
step=0
total=5

# 全局变量
declare -g choice=""
declare -ga ALL_IPS=()       # 存储所有IP地址
declare -ga USER_LIST=()     # 存储L2TP用户名
declare -ga VIRTUAL_IPS=()   # 存储L2TP虚拟IP
declare -g SOCKS5_USER=""    # SOCKS5用户名
declare -g SOCKS5_PASS=""    # SOCKS5密码
declare -g L2TP_UP=""        # L2TP密码
declare -g L2TP_USER=""      # L2TP用户名

# 文件路径定义
IP_FILE="/root/ip.txt"
PORT=1080
LOG_DIR="/var/log/xray"
CONFIG_PATH="/etc/xray/serve.toml"
SERVICE_PATH="/etc/systemd/system/xray.service"
NETWORK_SETUP_SCRIPT="/usr/local/bin/setup-multi-ip.sh"
NETWORK_SERVICE="/etc/systemd/system/multi-ip-setup.service"
XRAY_BIN="/usr/local/bin/xray"
PK="hostname123"
MAX_RETRIES=3
RETRY_INTERVAL=2
INTERFACE="eth0"  # 主网络接口

# 安装统计
install_stats=()

# 方框输出函数
box_msg() {
    local text="$1"
    local current_step=$((++step))
    local formatted_step="$(printf '%02d' $current_step)/$(printf '%02d' $total)"

    echo -e "\n${GREEN}┌──────────────────────────────────────────────────────────────┐"
    echo -e "│${WHITE} [${formatted_step}] ${text}${GREEN}"
    echo -e "└──────────────────────────────────────────────────────────────┘${NC}"
}

# 错误输出函数
box_err() {
    local text="$1"
    echo -e "\n${RED}┌──────────────────────────────────────────────────────────────┐"
    echo -e "│${WHITE} ✘ 错误：${text}${RED}"
    echo -e "└──────────────────────────────────────────────────────────────┘${NC}" >&2
    exit 1
}

# 成功提示函数
box_success() {
    local text="$1"
    echo -e "${GREEN}┌──────────────────────────────────────────────────────────────┐"
    echo -e "│${WHITE} ✅ ${text}${GREEN}"
    echo -e "└──────────────────────────────────────────────────────────────┘${NC}"
}

# 静默执行 apt 命令并显示进度
run_apt_silent() {
    local cmd="$1"
    local desc="$2"
    local start_time=$(date +%s)

    echo -e "   ${WHITE}▶ ${desc}...${NC}"

    # 执行 apt 命令并捕获输出
    if $cmd > /tmp/apt_output.log 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo -e "   ${WHITE}✔ ${desc}完成 (耗时 ${duration}s)${NC}"
        return 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo -e "   ${WHITE}❌ ${desc}失败 (耗时 ${duration}s)${NC}"
        return 1
    fi
}

# 静默执行 wget 命令并显示进度（样式与 apt 一致）
run_wget_silent() {
    local url="$1"
    local desc="$2"
    local output="$3"
    local start_time=$(date +%s)

    echo -e "   ${WHITE}▶ ${desc}...${NC}"

    if wget -q -O "$output" "$url" > /tmp/wget_output.log 2>&1; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo -e "   ${WHITE}✔ ${desc}完成 (耗时 ${duration}s)${NC}"
        return 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo -e "   ${WHITE}❌ ${desc}失败 (耗时 ${duration}s)${NC}"
        return 1
    fi
}

# 输入验证函数
read_with_validation() {
  local prompt="$1"
  local default="$2"
  local pattern="$3"
  local errmsg="$4"
  local timeout=${5:-10}
  local retries=3
  local input

  for ((i=0;i<retries;i++)); do
    read -t "$timeout" -rp "$prompt" input || input=""
    input=$(echo "$input" | tr -d '\r')
    if [ -z "$input" ]; then
      echo "$default"
      return 0
    fi
    if [[ "$input" =~ $pattern ]]; then
      echo "$input"
      return 0
    else
      echo -e "\n   ${WHITE}❗ 输入不合法：${errmsg}${NC}\n"
      timeout=10
    fi
  done
  echo "$default"
}

# 获取公网IP函数
get_public_ip() {
    local public_ip=""
    local api_servers=(
        "ifconfig.me"
        "api.ipify.org"
        "icanhazip.com"
        "ident.me"
        "4.ipw.cn"
    )

    for api in "${api_servers[@]}"; do
        public_ip=$(curl -s --connect-timeout 5 "$api" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
        if [[ $public_ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            # 检查是否是公网IP（非私有地址）
            if [[ ! $public_ip =~ ^10\. ]] && \
               [[ ! $public_ip =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] && \
               [[ ! $public_ip =~ ^192\.168\. ]] && \
               [[ ! $public_ip =~ ^127\. ]] && \
               [[ ! $public_ip =~ ^169\.254\. ]]; then
                echo "$public_ip"
                return 0
            else
                echo -e "   ${WHITE}⚠ 获取到的是私有IP: $public_ip，继续尝试...${NC}"
            fi
        fi
        sleep 1
    done

    echo -e "   ${WHITE}⚠ 无法获取公网IP，使用本地IP${NC}"
    echo "$LOCAL_IP"
}

# 清理网络配置函数
cleanup_network_config() {
    echo -e "\n${WHITE}🔧 清理之前的网络配置...${NC}"
    
    # 1. 清理网络子接口
    echo -e "   ${WHITE}▶ 清理网络子接口...${NC}"
    # 删除所有eth0的子接口
    for iface in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep "^eth0:" || true); do
        echo "      删除接口 $iface"
        sudo ip link delete "$iface" 2>/dev/null || true
    done
    
    # 2. 从主接口删除所有额外的IP地址（除了主IP）
    echo -e "   ${WHITE}▶ 清理主接口额外IP...${NC}"
    # 获取主接口的主IP
    local main_ip=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    
    # 删除所有非主IP的secondary地址
    for ip in $(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v "^$main_ip$"); do
        echo "      删除IP: $ip"
        sudo ip addr del "$ip"/32 dev "$INTERFACE" 2>/dev/null || true
    done
    
    # 3. 清理IPtables NAT规则
    echo -e "   ${WHITE}▶ 清理IPtables NAT规则...${NC}"
    # 清空整个POSTROUTING链
    sudo iptables -t nat -F POSTROUTING 2>/dev/null || true
    
    echo -e "   ${WHITE}✔ 网络配置清理完成${NC}"
    sleep 1
}

# 创建网络配置脚本（用于系统启动）
create_network_setup_script() {
    echo -e "   ${WHITE}▶ 创建网络配置脚本...${NC}"
    
    sudo cat > "$NETWORK_SETUP_SCRIPT" << 'EOF'
#!/bin/bash

set -e

# 网络配置脚本 - 用于系统启动时配置多IP
# 设置日志
LOG_FILE="/var/log/multi-ip-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# 主网络接口
INTERFACE="eth0"
IP_FILE="/root/ip.txt"

# 等待网络接口就绪
wait_for_interface() {
    echo "$(date): 等待网络接口 $INTERFACE 就绪..."
    
    local max_retries=30
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if ip link show "$INTERFACE" >/dev/null 2>&1; then
            echo "$(date): 网络接口 $INTERFACE 已就绪"
            return 0
        fi
        echo "$(date): 等待网络接口 $INTERFACE... (尝试 $((retry_count+1))/$max_retries)"
        sleep 2
        retry_count=$((retry_count + 1))
    done
    
    echo "$(date): 警告: 网络接口 $INTERFACE 未就绪，继续执行"
    return 0
}

# 清理旧配置
cleanup_old_config() {
    echo "$(date): 清理旧网络配置..."
    
    # 删除所有eth0的子接口
    for iface in $(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep "^${INTERFACE}:" || true); do
        ip link delete "$iface" 2>/dev/null || true
        echo "$(date): 删除接口 $iface"
    done
    
    # 等待网络接口稳定
    sleep 2
}

# 配置新IP
configure_new_ips() {
    echo "$(date): 开始配置新IP..."
    
    if [ ! -f "$IP_FILE" ]; then
        echo "$(date): 错误: IP文件 $IP_FILE 不存在"
        return 1
    fi
    
    # 读取IP文件
    ALL_IPS=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | tr -d '\r\n' | xargs)
        if [[ $line =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            ALL_IPS+=("$line")
        fi
    done < "$IP_FILE"
    
    if [ ${#ALL_IPS[@]} -eq 0 ]; then
        echo "$(date): 错误: 未在 $IP_FILE 中找到有效的IP地址"
        return 1
    fi
    
    echo "$(date): 找到 ${#ALL_IPS[@]} 个IP地址需要配置"
    
    # 为每个IP配置
    for ((i=0; i<${#ALL_IPS[@]}; i++)); do
        local ip="${ALL_IPS[$i]}"
        local sub_interface="${INTERFACE}:${i}"
        
        # 检查IP是否已经配置
        if ! ip addr show "$INTERFACE" 2>/dev/null | grep -q "inet $ip/"; then
            echo "$(date): 配置 $ip 到 $INTERFACE"
            
            # 添加IP地址
            if ! ip addr add "$ip"/24 dev "$INTERFACE" label "$sub_interface" 2>/dev/null; then
                echo "$(date): 警告: 无法添加IP $ip，可能已存在"
            fi
            
            # 启用接口
            ip link set "$sub_interface" up 2>/dev/null || true
            echo "$(date): 已配置: $ip"
            
            # 小延迟避免过快
            sleep 0.5
        else
            echo "$(date): IP $ip 已存在，跳过"
        fi
    done
    
    echo "$(date): IP配置完成"
    return 0
}

# 配置L2TP NAT规则（如果L2TP已安装）
configure_l2tp_nat() {
    echo "$(date): 检查L2TP配置..."
    
    # 检查是否有L2TP配置文件
    if [ ! -f "/etc/ipsec.conf" ] && [ ! -f "/etc/xl2tpd/xl2tpd.conf" ]; then
        echo "$(date): 未发现L2TP配置文件，跳过NAT规则配置"
        return 0
    fi
    
    echo "$(date): 配置L2TP NAT规则..."
    
    # 启用IP转发
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
    
    # 清理旧NAT规则
    iptables -t nat -F POSTROUTING 2>/dev/null || true
    
    # 读取IP文件
    ALL_IPS=()
    if [ -f "$IP_FILE" ]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line=$(echo "$line" | tr -d '\r\n' | xargs)
            if [[ $line =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                ALL_IPS+=("$line")
            fi
        done < "$IP_FILE"
    fi
    
    # 配置虚拟IP NAT规则（192.168.18.2-192.168.18.11）
    for i in "${!ALL_IPS[@]}"; do
        if [ $i -lt 10 ]; then  # 最多10个虚拟IP
            local virtual_ip="192.168.18.$((i+2))"
            local public_ip="${ALL_IPS[$i]}"
            
            echo "$(date): 配置SNAT: $virtual_ip -> $public_ip"
            iptables -t nat -A POSTROUTING -s "$virtual_ip" -j SNAT --to-source "$public_ip" 2>/dev/null || {
                echo "$(date): 警告: 无法添加SNAT规则 $virtual_ip -> $public_ip"
            }
        fi
    done
    
    echo "$(date): L2TP NAT规则配置完成"
    return 0
}

# 重启L2TP服务（如果已安装）
restart_l2tp_services() {
    echo "$(date): 检查并重启L2TP服务..."
    
    # 重启IPsec服务
    if command -v ipsec >/dev/null 2>&1; then
        echo "$(date): 重启IPsec服务..."
        ipsec stop >/dev/null 2>&1 || true
        sleep 2
        ipsec start >/dev/null 2>&1 || {
            echo "$(date): 警告: IPsec启动失败，尝试重启..."
            ipsec restart >/dev/null 2>&1 || true
        }
    fi
    
    # 重启xl2tpd服务
    if command -v xl2tpd >/dev/null 2>&1; then
        echo "$(date): 重启xl2tpd服务..."
        if systemctl list-unit-files | grep -q xl2tpd; then
            systemctl restart xl2tpd >/dev/null 2>&1 || {
                echo "$(date): 警告: xl2tpd服务重启失败"
            }
        elif [ -f "/etc/init.d/xl2tpd" ]; then
            /etc/init.d/xl2tpd restart >/dev/null 2>&1 || {
                echo "$(date): 警告: xl2tpd init脚本重启失败"
            }
        else
            pkill xl2tpd >/dev/null 2>&1 || true
            sleep 2
            xl2tpd >/dev/null 2>&1 || {
                echo "$(date): 警告: 直接启动xl2tpd失败"
            }
        fi
    fi
    
    echo "$(date): L2TP服务重启完成"
    return 0
}

# 主函数
main() {
    echo "$(date): ======= 开始多IP网络配置 ======="
    
    # 等待网络接口
    wait_for_interface
    
    # 清理旧配置
    cleanup_old_config
    
    # 配置新IP
    if ! configure_new_ips; then
        echo "$(date): 网络配置失败"
        return 1
    fi
    
    # 配置L2TP NAT规则
    configure_l2tp_nat
    
    # 重启L2TP服务
    restart_l2tp_services
    
    # 显示配置结果
    echo "$(date): 当前网络配置:"
    ip addr show "$INTERFACE" 2>/dev/null | grep "inet " || echo "  无IP配置"
    
    echo "$(date): ======= 多IP网络配置完成 ======="
    return 0
}

# 执行主函数
main "$@"
EOF

    # 设置权限
    sudo chmod +x "$NETWORK_SETUP_SCRIPT"
    sudo chown root:root "$NETWORK_SETUP_SCRIPT"
    
    echo -e "   ${WHITE}✔ 网络配置脚本创建完成${NC}"
}

# 创建网络配置服务
create_network_service() {
    echo -e "   ${WHITE}▶ 创建网络配置服务...${NC}"
    
    sudo cat > "$NETWORK_SERVICE" << EOF
[Unit]
Description=Multi-IP Network Setup
Wants=network-online.target
After=network-online.target systemd-networkd-wait-online.service
Before=xray.service

[Service]
Type=oneshot
ExecStart=$NETWORK_SETUP_SCRIPT
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    
    echo -e "   ${WHITE}✔ 网络配置服务创建完成${NC}"
}

# 菜单选择函数
show_menu() {
    local timeout=10  # 超时时间10秒
    local valid_choices=("1" "2" "3")
    
    while true; do
        echo -e "\n${GREEN}┌──────────────────────────────────────────────────────────────┐"
        echo -e "│${WHITE}         请选择要安装的代理类型：${GREEN}"
        echo -e "│${WHITE} 1. SOCKS5 代理 ${GREEN}"
        echo -e "│${WHITE} 2. L2TP 代理${GREEN}"
        echo -e "│${WHITE} 3. 同时安装两种代理（默认）${GREEN}"
        echo -e "└──────────────────────────────────────────────────────────────┘${NC}"

        # 读取输入，支持超时默认
        read -t "$timeout" -rp "请选择 (1/2/3，${timeout}秒内无输入将默认选择3)： " choice || {
            echo -e "\n${WHITE}ℹ 超时未输入，默认选择 3 - 同时安装两种代理${NC}"
            choice="3"
        }
        
        # 去除输入中的空格和换行符
        choice=$(echo "$choice" | tr -d ' \n\r')
        
        # 检查是否为有效选择
        case "$choice" in
            1)
                selected_proxy="socks5"
                echo -e "${GREEN}✔ 已选择：SOCKS5 代理${NC}"
                install_socks5_proxy
                break
                ;;
            2)
                selected_proxy="l2tp"
                echo -e "${GREEN}✔ 已选择：L2TP 代理${NC}"
                install_l2tp_proxy
                break
                ;;
            3|"")  # 空输入也视为默认选择3
                selected_proxy="both"
                echo -e "${GREEN}✔ 已选择：同时安装两种代理${NC}"
                install_both_proxies
                break
                ;;
            *)
                echo -e "${RED}❌ 无效选择：'$choice'，请输入 1、2 或 3${NC}"
                # 重新循环，让用户再次选择
                continue
                ;;
        esac
    done
}

# 生成随机账号密码
generate_credentials() {
    # 生成8位纯字母的USER/PASS
    local user=$(cat /dev/urandom 2>/dev/null | tr -dc 'a-zA-Z' | fold -w 8 | head -n 1 | tr -d '\n\r' || echo "user$(date +%s | cut -c1-4)")
    user=$(echo "$user" | cut -c1-8)

    # 生成8位纯字母的PASS
    local pass=$(cat /dev/urandom 2>/dev/null | tr -dc 'a-zA-Z' | fold -w 8 | head -n 1 | tr -d '\n\r' || echo "pass$(date +%s | cut -c1-4)")
    pass=$(echo "$pass" | cut -c1-8)

    # 生成8位纯数字的UP（用于L2TP）
    local up=$(cat /dev/urandom 2>/dev/null | tr -dc '0-9' | fold -w 8 | head -n 1 | tr -d '\n\r' || echo "$(date +%s | tr -dc '0-9' | cut -c1-8)")
    up=$(echo "$up" | cut -c1-8)

    echo "$user:$pass:$up"
}

# 网络配置函数（Netplan持久化版本，替换原临时子接口配置）
network_config() {
    box_msg "开始进行网络配置..."
    
    # 1. 基础合法性检查
    if [ ! -f "$IP_FILE" ]; then
        box_err "IP信息文件 '$IP_FILE' 不存在，请确认路径"
    fi

    # 转换IP文件为Unix格式（去除Windows换行符）
    dos2unix "$IP_FILE" 2>/dev/null || true  # 忽略没有dos2unix的情况

    # 读取IP文件内容到ALL_IPS数组，同时清除特殊字符
    echo -e "\n📖 读取IP列表文件..."
    ALL_IPS=()

    # 使用mapfile更可靠地读取所有行，包括最后一行（即使没有换行符）
    mapfile -t lines < "$IP_FILE"

    for line in "${lines[@]}"; do
        # 清除行尾的控制字符（包括\r）并跳过空行
        cleaned_line=$(echo "$line" | tr -d '\r' | xargs)
        if [ -n "$cleaned_line" ]; then
            ALL_IPS+=("$cleaned_line")
        fi
    done

    # 检查是否读取到IP
    if [ ${#ALL_IPS[@]} -eq 0 ]; then
        box_err "IP信息文件 '$IP_FILE' 中未找到有效的IP地址"
    fi
    echo "✔ 成功读取到 ${#ALL_IPS[@]} 个IP地址"

    # 2. 用Netplan配置多IP地址（持久化，替代原ifconfig/ip addr临时配置）
    echo -e "\n🌐 配置Netplan多IP网络（持久化） >>> "

    # 定义Netplan配置文件路径
    NETPLAN_CONFIG="/etc/netplan/zz-ctims.yaml"

    # 提取内网网关（自动获取当前默认网关，兼容手动指定）
    GATEWAY=$(ip route show default | awk '/default/ {print $3}' 2>/dev/null)
    if [ -z "$GATEWAY" ]; then
        box_err "无法自动获取内网网关，请手动配置GATEWAY变量（如GATEWAY=\"192.168.1.1\"）"
    fi

    # 生成Netplan配置文件内容（严格遵循YAML格式：2个空格缩进，无Tab）
    echo "  生成Netplan配置文件：$NETPLAN_CONFIG"
    sudo tee "$NETPLAN_CONFIG" > /dev/null 2>&1 << EOF
network:
  ethernets:
    $INTERFACE:  # 对应物理网卡名称（从脚本全局变量INTERFACE获取）
      addresses:
EOF

    # 遍历ALL_IPS数组，拼接所有IP地址（格式：IP/24，自动清理无效字符）
    for ip in "${ALL_IPS[@]}"; do
        cleaned_ip=$(echo "$ip" | tr -d '\r' | xargs)
        sudo tee -a "$NETPLAN_CONFIG" > /dev/null 2>&1 << EOF
        - $cleaned_ip/24
EOF
    done

    # 补充网关、DNS、版本、渲染器等必要配置
    sudo tee -a "$NETPLAN_CONFIG" > /dev/null 2>&1 << EOF
      gateway4: $GATEWAY  # 内网网关（自动获取或手动指定）
      nameservers:
        addresses: [8.8.8.8, 114.114.114.114, 223.5.5.5]  # DNS服务器，确保解析正常
  version: 2
  renderer: NetworkManager  # 按需修改：服务器版改为networkd，桌面版保留NetworkManager
EOF

    # 检查配置文件生成是否成功
    if [ ! -f "$NETPLAN_CONFIG" ]; then
        box_err "Netplan配置文件生成失败"
    fi
    echo "  ✔ Netplan配置文件生成完成"

    # 关键：设置Netplan配置文件正确权限（要求600，避免安全警告和配置失效）
    sudo chmod 600 "$NETPLAN_CONFIG"

    # 应用Netplan配置（使多IP生效）
    echo "  应用Netplan配置，等待网络稳定..."
    sudo netplan apply > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        box_err "Netplan配置应用失败，请检查配置文件格式、IP合法性或网关正确性"
    fi

    # 等待1秒，确保网络接口完全加载
    sleep 1

    # 验证IP是否配置成功
    echo "  验证配置的IP是否生效..."
    ip_count=0
    for ip in "${ALL_IPS[@]}"; do
        cleaned_ip=$(echo "$ip" | tr -d '\r' | xargs)
        if ip addr show "$INTERFACE" | grep -q "$cleaned_ip"; then
            ip_count=$((ip_count + 1))
        fi
    done

    if [ $ip_count -eq ${#ALL_IPS[@]} ]; then
        echo "  ✔ 所有IP（共$ip_count个）均配置生效"
    else
        echo "  ⚠ 仅$ip_count个IP生效，部分IP配置失败（可检查IP是否冲突、网段是否匹配）"
    fi
}
# SOCKS5代理安装函数
install_socks5_proxy() {
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${WHITE}      开始安装 SOCKS5 代理 ${NC}"
    echo -e "${GREEN}========================================${NC}\n"

    local socks5_credentials=$(generate_credentials)
    SOCKS5_USER=$(echo "$socks5_credentials" | cut -d: -f1)
    SOCKS5_PASS=$(echo "$socks5_credentials" | cut -d: -f2)
    SOCKS5_UP=$(echo "$socks5_credentials" | cut -d: -f3)

    # 重置步骤计数器
    step=0
    total=7

    # 如果还没有进行网络配置，则执行
    if [ ${#ALL_IPS[@]} -eq 0 ]; then
        network_config
    fi

    # 创建网络配置脚本和服务
    create_network_setup_script
    create_network_service

    box_msg "开始进行下载依赖，时间较长，请耐心等待..."

    if sudo systemctl is-active --quiet xray; then
        echo "⚠ 检测到 代理 服务正在运行，执行停止操作..."
        sudo systemctl stop xray
        if [ $? -eq 0 ]; then
            echo "服务已成功停止"
        else
            echo "停止服务失败，将尝试强制终止残留进程"
            sudo pkill -f "$XRAY_BIN" > /dev/null 2>&1
            sleep 1
        fi
    else
        echo "服务当前未运行，无需停止"
    fi

    # 下载Xray二进制文件
    box_msg "下载socks5核心文件xray..."
    run_apt_silent "apt install -y unzip" "安装unzip解压工具"
    local XRAY_ZIP="/tmp/Xray-linux-64.zip"
    run_wget_silent "https://hub.cmoko.com/https://github.com/XTLS/Xray-core/releases/download/v1.5.3/Xray-linux-64.zip" "下载 Xray 官方压缩包" "$XRAY_ZIP" || return 1
    echo -e "   ${WHITE}▶ 解压 Xray 核心文件...${NC}"
    unzip -q -o "$XRAY_ZIP" xray -d /usr/local/bin/ > /dev/null 2>&1
    rm -f "$XRAY_ZIP"
    chmod +x "$XRAY_BIN"

    box_msg "开始配置socks5账号和密码....."

    # 配置Socks代理参数（校验8位纯字母）
    echo -e "\n 配置Socks代理参数（10秒内不输入则用默认值）"
    SOCKS5_USER=$(read_with_validation "请输入SOCKS5账号（8位纯字母，默认：$SOCKS5_USER）：" "$SOCKS5_USER" '^[a-zA-Z]{8}$' "必须是8位纯字母")
    SOCKS5_PASS=$(read_with_validation "请输入SOCKS5密码（8位纯字母，默认：$SOCKS5_PASS）：" "$SOCKS5_PASS" '^[a-zA-Z]{8}$' "必须是8位纯字母")

    echo -e "\n✔ 代理参数确认：账号=$SOCKS5_USER，端口=$PORT（固定），密码=$SOCKS5_PASS"

    box_msg "开始安装部署SOCKS5代理"
    
    # 6. 生成Xray配置文件（包含所有IP）
    echo -e " 生成 代理 配置文件（包含所有IP）..."
    sudo mkdir -p "$LOG_DIR" /etc/xray
    sudo tee "$CONFIG_PATH" > /dev/null 2>&1 << EOF
# Xray 多IP Socks5 代理配置
# 配置说明：包含固定IP和文件中所有IP
# 生成时间：$(date +"%Y-%m-%d %H:%M:%S")

[log]
loglevel = "info"
access = "$LOG_DIR/access.log"
error = "$LOG_DIR/error.log"

[routing]
EOF

    # 生成路由规则
    echo "  正在生成路由规则..."
    for inner_ip in "${ALL_IPS[@]}"; do
        # 提取IP最后一段并确保没有控制字符
        tag=$(echo "$inner_ip" | awk -F '.' '{print $4}' | tr -d '\r')
        sudo tee -a "$CONFIG_PATH" > /dev/null 2>&1 << EOF
  [[routing.rules]]
  type = "field"
  inboundTag = "ip-$tag"
  outboundTag = "ip-$tag"

EOF
    done

    # 生成入站+出站配置
    for inner_ip in "${ALL_IPS[@]}"; do
        # 提取IP最后一段并确保没有控制字符
        tag=$(echo "$inner_ip" | awk -F '.' '{print $4}' | tr -d '\r')
        sudo tee -a "$CONFIG_PATH" > /dev/null 2>&1 << EOF
[[inbounds]]
listen = "$inner_ip"
port = $PORT
protocol = "socks"
tag = "ip-$tag"
[inbounds.settings]
auth = "password"
udp = true
[[inbounds.settings.accounts]]
user = "$SOCKS5_USER"
pass = "$SOCKS5_PASS"

[[outbounds]]
sendThrough = "$inner_ip"
protocol = "freedom"
tag = "ip-$tag"

EOF
    done

    sudo chmod 644 "$CONFIG_PATH"
    sudo chown root:root "$CONFIG_PATH"

    # 7. 配置并启动Xray系统服务（修改版，依赖网络配置服务）
    echo -e "\n 配置 代理 系统服务..."
sudo tee "$SERVICE_PATH" > /dev/null 2>&1 << EOF
[Unit]
Description=Xray Service (Multi-IP SOCKS5 Proxy)
Wants=network-online.target multi-ip-setup.service
After=network-online.target systemd-networkd-wait-online.service multi-ip-setup.service
Requires=multi-ip-setup.service

[Service]
Type=simple
ExecStart=/usr/local/bin/xray run -c /etc/xray/serve.toml
Restart=always
RestartSec=5
User=root
LimitNOFILE=65535
# 启动前等待网络配置完成
ExecStartPre=/bin/sleep 3

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    echo "✔ 代理 服务文件配置完成"

    # 启动网络配置服务
    echo -e " 启动网络配置服务..."
    sudo systemctl enable multi-ip-setup.service > /dev/null 2>&1
    
    # 直接运行网络配置脚本
    echo -e " 执行网络配置..."
    sudo bash "$NETWORK_SETUP_SCRIPT"
    
    # 检查网络配置服务状态
    if sudo systemctl is-enabled multi-ip-setup.service >/dev/null 2>&1; then
        echo "✔ 网络配置服务已启用"
    else
        echo "⚠ 网络配置服务启用失败"
    fi

    # 启动Xray服务并检查状态
    sudo systemctl stop xray > /dev/null 2>&1
    sudo systemctl start xray
    sleep 3
    if sudo systemctl is-active --quiet xray; then
        sudo systemctl enable xray > /dev/null 2>&1
        echo "✔ 代理 服务启动成功"
    else
        echo "❌ 代理 服务启动失败，最近10条错误日志："
        sudo journalctl -u xray -n 10 --no-pager
        return 1
    fi

    # 记录安装信息
    install_stats+=("SOCKS5代理安装完成")

    return 0
}

# L2TP代理安装函数
install_l2tp_proxy() {
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${WHITE}      开始安装 L2TP 代理${NC}"
    echo -e "${GREEN}========================================${NC}\n"

    local l2tp_credentials=$(generate_credentials)
    L2TP_USER=$(echo "$l2tp_credentials" | cut -d: -f1)
    L2TP_PASS=$(echo "$l2tp_credentials" | cut -d: -f2)
    L2TP_UP=$(echo "$l2tp_credentials" | cut -d: -f3)

    # 重置步骤计数器
    step=0
    total=7

    # 如果还没有进行网络配置，则执行
    if [ ${#ALL_IPS[@]} -eq 0 ]; then
        network_config
    fi

    # 创建网络配置脚本和服务
    create_network_setup_script
    create_network_service

    box_msg "开始进行下载依赖，时间较长，请耐心等待..."

    # 使用静默 apt 执行函数
    run_apt_silent "apt update -y" "更新软件包列表"
    run_apt_silent "apt install -y xl2tpd strongswan curl" "安装L2TP和IPSec依赖"

    box_msg "开始配置L2TP账号和密码..."

    # 配置L2TP代理参数（校验8位纯字母账号和8位纯数字密码）
    echo -e "\n 配置L2TP代理【账号】和【密码】（10秒内不输入则用默认值）"
    L2TP_USER=$(read_with_validation "请输入L2TP账号（8位纯字母，默认：$L2TP_USER）：" "$L2TP_USER" '^[a-zA-Z]{8}$' "必须是8位纯字母")
    L2TP_UP=$(read_with_validation "请输入L2TP密码（8位纯数字，默认：$L2TP_UP）：" "$L2TP_UP" '^[0-9]{8}$' "必须是8位纯数字")

    box_msg "安装L2TP代理"
    
    # 初始化用户列表和虚拟IP列表
    USER_LIST=()
    VIRTUAL_IPS=()
    
    # 生成10个用户和对应的虚拟IP
    for i in {0..9}; do
        # 生成8位字母数字混合的用户名
        local user=$(cat /dev/urandom 2>/dev/null | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1 | tr -d '\n\r')
        user=$(echo "$user" | cut -c1-8)
        USER_LIST+=("$user")
        
        # 生成虚拟IP (192.168.18.x)
        local virtual_ip="192.168.18.$((i+2))"
        VIRTUAL_IPS+=("$virtual_ip")
    done

    # 先备份原有配置
    cp /etc/sysctl.conf /etc/sysctl.conf.bak."$(date +%Y%m%d)"

    # 添加L2TP/IPSec必需的内核参数
    # 先删除可能存在的旧配置
    sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
    sed -i '/net.ipv4.conf.all.accept_redirects/d' /etc/sysctl.conf
    sed -i '/net.ipv4.conf.all.send_redirects/d' /etc/sysctl.conf
    sed -i '/net.ipv4.conf.default.rp_filter/d' /etc/sysctl.conf
    sed -i '/net.ipv4.conf.default.accept_source_route/d' /etc/sysctl.conf
    sed -i '/net.ipv4.icmp_echo_ignore_broadcasts/d' /etc/sysctl.conf
    sed -i '/net.ipv4.icmp_ignore_bogus_error_responses/d' /etc/sysctl.conf
    
    cat >> /etc/sysctl.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
EOF

    sysctl -p >/dev/null && sleep 1

    # 验证ipsec命令是否存在（关键检查）
    if ! command -v ipsec &> /dev/null; then
        box_err "未找到ipsec命令，请手动安装strongswan:
Debian/Ubuntu: sudo apt install strongswan
CentOS/RHEL: sudo yum install strongswan
Fedora: sudo dnf install strongswan"
    fi

    # 验证xl2tpd是否安装
    if ! command -v xl2tpd &> /dev/null; then
        box_err "未找到xl2tpd命令，请手动安装xl2tpd"
    fi

    # ---------------- 配置文件 ----------------
    cat >/etc/ipsec.conf <<'EOF'
version 2.0
config setup
    protostack=netkey
    nhelpers=0
    uniqueids=no
    virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:10.0.0.0/12
conn l2tp-psk
    rightsubnet=vhost:%priv
    also=l2tp-psk-nonat
conn l2tp-psk-nonat
    authby=secret
    pfs=no
    auto=add
    keyingtries=3
    rekey=no
    ikelifetime=8h
    keylife=1h
    type=transport
    left=%any
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    dpddelay=40
    dpdtimeout=130
    dpdaction=clear
    sha2-truncbug=yes
EOF

    echo "%any %any : PSK \"$PK\"" >/etc/ipsec.secrets
    chmod 600 /etc/ipsec.secrets

    cat >/etc/xl2tpd/xl2tpd.conf <<'EOF'
[global]
ipsec saref = yes
listen-addr = 0.0.0.0
port = 1701
[lns default]
ip range = 192.168.18.2-192.168.18.254
local ip = 192.168.18.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

    cat >/etc/ppp/options.xl2tpd <<'EOF'
ipcp-accept-local
ipcp-accept-remote
require-mschap-v2
ms-dns 8.8.8.8
ms-dns 8.8.4.4
noccp
auth
hide-password
idle 0
mtu 1410
mru 1410
nodefaultroute
debug
proxyarp
connect-delay 5000
EOF

    :>/etc/ppp/chap-secrets
    for i in {0..9}; do
      printf '%s l2tpd %s %s\n' "${USER_LIST[i]}" "$L2TP_UP" "${VIRTUAL_IPS[i]}"
    done >>/etc/ppp/chap-secrets
    chmod 600 /etc/ppp/chap-secrets

    # 启动网络配置服务
    echo -e " 启动网络配置服务..."
    sudo systemctl enable multi-ip-setup.service > /dev/null 2>&1
    
    # 直接运行网络配置脚本
    echo -e " 执行网络配置..."
    sudo bash "$NETWORK_SETUP_SCRIPT"
    
    # 检查网络配置服务状态
    if sudo systemctl is-enabled multi-ip-setup.service >/dev/null 2>&1; then
        echo "✔ 网络配置服务已启用"
    else
        echo "⚠ 网络配置服务启用失败"
    fi

    # ---------------- 启动服务 ----------------
    # 停止可能正在运行的IPsec进程
    ipsec stop >/dev/null 2>&1 || true

    # 启动IPsec服务
    echo "使用ipsec命令启动IPsec服务..."
    if ! ipsec start >/dev/null 2>&1; then
        if ! ipsec restart >/dev/null 2>&1; then
            box_err "IPsec服务启动失败，请手动执行 'ipsec start' 检查错误"
        fi
    fi

    # 检查IPsec状态
    if ! ipsec status >/dev/null 2>&1; then
        box_err "IPsec服务启动后状态异常"
    fi

    # 启动xl2tpd服务
    echo "启动l2tp服务..."
    if systemctl list-unit-files | grep -q xl2tpd; then
        systemctl restart xl2tpd >/dev/null 2>&1
    elif [ -f "/etc/init.d/xl2tpd" ]; then
        /etc/init.d/xl2tpd restart >/dev/null 2>&1
    else
        # 尝试直接运行xl2tpd
        echo "尝试直接启动l2tp进程..."
        pkill xl2tpd >/dev/null 2>&1 || true
        xl2tpd >/dev/null 2>&1 || box_err "启动代理失败"
    fi

    # 验证xl2tpd是否运行
    if ! pgrep xl2tpd >/dev/null 2>&1; then
        box_err "xl2tpd 进程未运行"
    fi

    # 创建L2TP服务的网络依赖
    cat > /etc/systemd/system/xl2tpd.service.d/network-dependency.conf 2>/dev/null || true << EOF
[Unit]
Wants=multi-ip-setup.service
After=multi-ip-setup.service
EOF

    systemctl daemon-reload >/dev/null 2>&1 || true

    # ---------------- NAT 规则 ----------------
    # 先清除可能存在的旧规则
    iptables -t nat -F POSTROUTING 2>/dev/null || true
    
    # 添加新的NAT规则
    for i in "${!ALL_IPS[@]}"; do
      iptables -t nat -A POSTROUTING -s "${VIRTUAL_IPS[i]}" \
               -j SNAT --to-source "${ALL_IPS[i]}"
      echo "  ✔ 为 ${VIRTUAL_IPS[i]} 配置SNAT到 ${ALL_IPS[i]}"
    done

    # 记录安装信息
    install_stats+=("L2TP代理安装完成")

    return 0
}

# 同时安装两种代理
install_both_proxies() {
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${WHITE}      开始同时安装两种代理${NC}"
    echo -e "${GREEN}========================================${NC}\n"

    # 先执行网络配置
    network_config

    # 创建网络配置脚本和服务
    create_network_setup_script
    create_network_service

    # 安装SOCKS5代理
    echo -e "\n${WHITE}>>> 开始安装SOCKS5代理...${NC}"
    if install_socks5_proxy; then
        echo -e "${GREEN}✅ SOCKS5代理安装成功${NC}"
    else
        echo -e "${RED}❌ SOCKS5代理安装失败，继续安装L2TP代理...${NC}"
    fi

    # 安装L2TP代理
    echo -e "\n${WHITE}>>> 开始安装L2TP代理...${NC}"
    if install_l2tp_proxy; then
        echo -e "${GREEN}✅ L2TP代理安装成功${NC}"
    else
        echo -e "${RED}❌ L2TP代理安装失败${NC}"
    fi

    # 显示所有安装结果
    show_installation_summary "both"
}

# 显示安装摘要
show_installation_summary() {
    local proxy_type="$1"
    
    echo -e "\n${GREEN}┌──────────────────────────────────────────────────────────────┐"
    echo -e "│${WHITE}                   安装完成汇总${GREEN}"
    echo -e "└──────────────────────────────────────────────────────────────┘${NC}"

    # 显示Socks5代理信息
    if [ "$proxy_type" = "socks5" ] || [ "$proxy_type" = "both" ]; then
        echo "========================================"
        echo "Socks5 代理配置信息"
        echo "========================================"
        >/root/socks5.txt  # 清空文件
        
        for inner_ip in "${ALL_IPS[@]}"; do
            retries=3
            retry_count=0
            public_ip=""

            while [ -z "$public_ip" ] && [ $retry_count -lt $retries ]; do
                if [ $retry_count -gt 0 ]; then
                    sleep 1
                fi
                public_ip=$(curl --interface "$inner_ip" -s --max-time 20 4.ipw.cn 2>/dev/null || true)
                public_ip=$(echo "$public_ip" | tr -d '\n\r ' | xargs)
                [[ $public_ip =~ ^[0-9.]+$ ]] && break
                retry_count=$((retry_count + 1))
            done

            if [ -n "$public_ip" ] && [[ $public_ip =~ ^[0-9.]+$ ]]; then
                echo "${public_ip}/${PORT}/${SOCKS5_USER}/${SOCKS5_PASS}"
                echo "${public_ip}/${PORT}/${SOCKS5_USER}/${SOCKS5_PASS}" >> /root/socks5.txt
            else
                echo "获取失败: $inner_ip"
                echo "获取失败: $inner_ip" >> /root/socks5.txt
            fi
        done
        echo "========================================"
    fi

    # 显示L2TP代理信息
    if [ "$proxy_type" = "l2tp" ] || [ "$proxy_type" = "both" ]; then
        echo "========================================"
        echo "l2tp 代理配置信息"
        echo "========================================"
        >/root/l2tp.txt
        
        # 检查USER_LIST是否已初始化
        if [ ${#USER_LIST[@]} -eq 0 ]; then
            echo "L2TP用户列表未初始化"
        else
            for i in "${!ALL_IPS[@]}"; do
                # 只显示已配置的用户（最多10个）
                if [ $i -lt ${#USER_LIST[@]} ]; then
                    pub=""
                    for ((t=0;t<MAX_RETRIES;t++)); do
                        pub=$(curl -s --interface "${ALL_IPS[i]}" --max-time 5 "icanhazip.com") && break
                        sleep "$RETRY_INTERVAL"
                    done
                    
                    [[ $pub =~ ^[0-9.]+$ ]] || pub='未获取到公网IP'
                    line="公网IP:$pub 用户名:${USER_LIST[i]} 密码:$L2TP_UP 预共享密钥:$PK 客户端虚拟IP:${VIRTUAL_IPS[i]}"
                    echo "$line" | tee -a /root/l2tp.txt
                fi
            done
        fi
        echo "========================================"
    fi

    echo -e "\n${GREEN}┌──────────────────────────────────────────────────────────────┐"
    echo -e "│${WHITE}                    重启说明${GREEN}"
    echo -e "│${WHITE}  已创建自动网络配置服务，服务器重启后:${GREEN}"
    echo -e "│${WHITE}  1. 系统会先配置所有IP地址${GREEN}"
    echo -e "│${WHITE}  2. 自动配置L2TP的NAT规则${GREEN}"
    echo -e "│${WHITE}  3. 重启L2TP相关服务${GREEN}"
    echo -e "│${WHITE}  4. 然后自动启动代理服务${GREEN}"
    echo -e "│${WHITE}  5. 无需手动干预${GREEN}"
    echo -e "└──────────────────────────────────────────────────────────────┘${NC}"

    box_success "所有配置流程已完成！"
}

# 主函数
main() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}请使用root权限运行此脚本${NC}"
        exit 1
    fi

    echo -e "${GREEN}┌──────────────────────────────────────────────────────────────┐"
    echo -e "│${WHITE}                  代理安装脚本${GREEN}"
    echo -e "└──────────────────────────────────────────────────────────────┘${NC}"

    show_menu

    if [ "$choice" = "1" ] && [ -n "$SOCKS5_USER" ]; then
        show_installation_summary "socks5"
    elif [ "$choice" = "2" ] && [ -n "$L2TP_USER" ]; then
        show_installation_summary "l2tp"
    fi
}

main "$@"
