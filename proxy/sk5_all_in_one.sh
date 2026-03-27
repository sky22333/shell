#!/bin/bash
# Socks5 一键部署与流量控制脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 全局变量
WORK_DIR="/opt/sk5"
CONF_VIPS="vips.txt"
CONF_VLANS="vlans.txt"
IP_FILE="$WORK_DIR/ip_nic.txt"
MON_CHAIN="traffic_sk5"

# 工具函数
function print_msg() { echo -e "${GREEN}[INFO]${PLAIN} $1"; }
function print_err() { echo -e "${RED}[ERROR]${PLAIN} $1"; }
function print_warn() { echo -e "${YELLOW}[WARN]${PLAIN} $1"; }

function check_root() {
    [[ $EUID -ne 0 ]] && print_err "必须使用 root 用户运行此脚本!" && exit 1
}

function check_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
            print_err "当前系统为 $ID，本脚本仅支持 Ubuntu 和 Debian 系统。"
            exit 1
        fi
    else
        print_err "无法识别的操作系统。"
        exit 1
    fi
}

function install_deps() {
    print_msg "正在安装依赖包 (dante-server, net-tools, curl, iptables)..."
    apt-get update -y -q > /dev/null
    apt-get install -y dante-server net-tools curl iptables dos2unix > /dev/null 2>&1
    systemctl disable danted > /dev/null 2>&1
    systemctl stop danted > /dev/null 2>&1
    mkdir -p $WORK_DIR
}

# 动态获取主网卡和IP
function get_main_network_info() {
    MAIN_IF=$(ip route | grep default | awk '{print $5}' | head -n1)
    MAIN_IP=$(ip -4 addr show $MAIN_IF | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
    MAIN_GW=$(ip route | grep default | awk '{print $3}' | head -n1)
    MAIN_SUBNET=$(ip route show dev $MAIN_IF scope link | awk '{print $1}' | head -n1)
    
    if [[ -z "$MAIN_IF" || -z "$MAIN_IP" ]]; then
        print_err "无法获取主网卡或主IP，请检查网络配置。"
        exit 1
    fi
}

# 交互式配置
function interactive_config() {
    local rand_port=$((RANDOM % 50000 + 10000))
    read -p "请输入 Socks5 端口 [回车默认随机: $rand_port]: " PORT
    PORT=${PORT:-$rand_port}

    local rand_user=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 8)
    while true; do
        read -p "请输入 Socks5 用户名 (4-12位字母数字) [回车默认随机: $rand_user]: " USERNAME
        USERNAME=${USERNAME:-$rand_user}
        if [[ "$USERNAME" =~ ^[a-zA-Z0-9]{4,12}$ ]]; then break; else print_err "格式错误！"; fi
    done

    local rand_pass=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 10)
    while true; do
        read -p "请输入 Socks5 密码 (最长12位) [回车默认随机: $rand_pass]: " PASSWORD
        PASSWORD=${PASSWORD:-$rand_pass}
        if [[ "$PASSWORD" =~ ^[a-zA-Z0-9_]{1,12}$ ]]; then break; else print_err "格式错误！"; fi
    done

    read -p "请输入每个IP的月流量限制(MB) [回车默认: 51200]: " MAX_TRAFFIC
    MAX_TRAFFIC=${MAX_TRAFFIC:-51200}

    # 创建系统用户
    if id "$USERNAME" &>/dev/null; then
        print_warn "用户 $USERNAME 已存在，正在更新密码..."
    else
        useradd --shell /usr/sbin/nologin "$USERNAME"
    fi
    echo "$USERNAME:$PASSWORD" | chpasswd
}

# 网络与多IP配置
function setup_network() {
    print_msg "配置多 IP 与路由规则..."
    > $IP_FILE
    
    # 记录主网卡
    echo "$MAIN_IP $PORT tcp $MAX_TRAFFIC 主网卡" >> $IP_FILE

    # 处理虚拟IP (vips.txt)
    if [[ -f "$CONF_VIPS" ]]; then
        dos2unix $CONF_VIPS > /dev/null 2>&1
        local idx=1
        while read -r vip; do
            [[ -z "$vip" ]] && continue
            ip addr add "$vip/24" dev "$MAIN_IF" 2>/dev/null
            echo "$vip $PORT tcp $MAX_TRAFFIC 虚拟IP_$idx" >> $IP_FILE
            ((idx++))
        done < "$CONF_VIPS"
    else
        print_warn "未发现 $CONF_VIPS，跳过虚拟IP配置。(如需配置请在脚本同目录创建此文件，每行一个IP)"
    fi

    # 处理 VLAN (vlans.txt)
    if [[ -f "$CONF_VLANS" ]]; then
        dos2unix $CONF_VLANS > /dev/null 2>&1
        local idx=1
        while read -r line; do
            [[ -z "$line" ]] && continue
            read -r vip vlan_id mac <<< "$line"
            local dev_name="vlan_${vlan_id}"
            
            ip link add link "$MAIN_IF" name "$dev_name" type vlan id "$vlan_id" 2>/dev/null
            ip link set dev "$dev_name" address "$mac" 2>/dev/null
            ip addr add "$vip/24" dev "$dev_name" 2>/dev/null
            ip link set dev "$dev_name" up
            
            # 策略路由
            local rt_table=$((100 + idx))
            ip route add default via "$MAIN_GW" dev "$dev_name" table "$rt_table" 2>/dev/null
            ip route add "$MAIN_SUBNET" dev "$dev_name" table "$rt_table" 2>/dev/null
            ip rule add from "$vip" table "$rt_table" 2>/dev/null

            echo "$vip $PORT tcp $MAX_TRAFFIC VLAN网卡_$idx" >> $IP_FILE
            ((idx++))
        done < "$CONF_VLANS"
    else
        print_warn "未发现 $CONF_VLANS，跳过 VLAN 网卡配置。"
    fi
}

# Dante 代理配置
function setup_dante() {
    print_msg "配置 Dante Socks5 代理服务..."
    
    # 杀掉旧进程
    killall -9 danted 2>/dev/null
    rm -rf /etc/systemd/system/danted@.service
    
    # 生成 Systemd 模板
    cat << 'EOF' > /etc/systemd/system/sk5-danted@.service
[Unit]
Description=Dante SOCKS v5 proxy daemon (Instance %i)
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/danted -f /etc/danted-%i.conf
Restart=always
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload

    # 为每个 IP 生成独立配置并启动
    while read -r line; do
        read -r ip port proto max remark <<< "$line"
        local conf="/etc/danted-${ip}.conf"
        
        cat << EOF > "$conf"
logoutput: syslog
internal: $ip port = $port
external: $ip
socksmethod: username
clientmethod: none
user.privileged: root
user.notprivileged: nobody
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect error
}
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect error
}
EOF
        systemctl enable sk5-danted@${ip} > /dev/null 2>&1
        systemctl restart sk5-danted@${ip}
    done < "$IP_FILE"
}

# 流量监控守护进程
function setup_traffic_monitor() {
    print_msg "配置流量监控与超限封禁服务..."
    
    # 生成监控脚本
    cat << 'EOF' > $WORK_DIR/monitor.sh
#!/bin/bash
MON_CHAIN="traffic_sk5"
IP_FILE="/opt/sk5/ip_nic.txt"

# 初始化 iptables
iptables -Z $MON_CHAIN 2>/dev/null
iptables -X $MON_CHAIN 2>/dev/null
iptables -N $MON_CHAIN 2>/dev/null

while read -r line; do
    read -r ip port proto max remark <<< "$line"
    iptables -A $MON_CHAIN -d $ip -p tcp --dport $port -j RETURN
done < $IP_FILE

iptables -D INPUT -j $MON_CHAIN 2>/dev/null
iptables -I INPUT 1 -j $MON_CHAIN

while true; do
    while read -r line; do
        read -r ip port proto max remark <<< "$line"
        # 使用 -vxL 获取精确的 bytes 字节数，避免单位换算错误
        bytes=$(iptables -vxL $MON_CHAIN | grep "dpt:$port" | grep "$ip" | awk '{print $2}' | head -n1)
        if [[ -n "$bytes" ]]; then
            # 转换为 MB
            mb=$((bytes / 1048576))
            if [[ $mb -ge $max ]]; then
                # 如果超过限制且还没被 DROP，则插入 DROP 规则
                if ! iptables -C $MON_CHAIN -d $ip -p tcp --dport $port -j DROP 2>/dev/null; then
                    iptables -I $MON_CHAIN 1 -d $ip -p tcp --dport $port -j DROP
                    echo "$(date): $ip 流量超限 ($mb MB >= $max MB), 已封禁." >> /opt/sk5/ban.log
                fi
            fi
        fi
    done < $IP_FILE
    sleep 15
done
EOF
    chmod +x $WORK_DIR/monitor.sh

    # 注册 Systemd 服务
    cat << 'EOF' > /etc/systemd/system/sk5-monitor.service
[Unit]
Description=Socks5 Traffic Monitor
After=network.target

[Service]
Type=simple
ExecStart=/opt/sk5/monitor.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable sk5-monitor > /dev/null 2>&1
    systemctl restart sk5-monitor
}

# 打印信息
function print_summary() {
    print_msg "安装与配置完成！代理节点信息如下："
    echo -e "========================================================================="
    printf " %-16s | %-6s | %-12s | %-12s | %-15s\n" "公网/私有IP" "端口" "用户名" "密码" "备注(限额)"
    echo -e "========================================================================="
    
    while read -r line; do
        read -r ip port proto max remark <<< "$line"
        # 尝试获取每个内网IP对应的公网出口IP (可能会有延迟)
        pub_ip=$(curl -s --interface "$ip" --connect-timeout 3 ipv4.icanhazip.com)
        [[ -z "$pub_ip" ]] && pub_ip="$ip"
        printf " %-16s | %-6s | %-12s | %-12s | %-15s\n" "$pub_ip" "$port" "$USERNAME" "$PASSWORD" "$remark(${max}MB)"
    done < "$IP_FILE"
    echo -e "========================================================================="
    echo "使用提示："
    echo "1. 代理服务已作为 systemd 进程运行 (sk5-danted@IP)"
    echo "2. 流量监控已在后台运行并随开机自启 (sk5-monitor)"
    echo "3. 若被封禁，流量将在下个月（或手动重启服务器）重置。"
}

# =========================================================
# 卸载功能
# =========================================================
function uninstall() {
    print_warn "即将卸载 Socks5 代理服务及所有配置，这会中断现有的代理连接！"
    read -p "确定要卸载吗？[y/N]: " confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        print_msg "已取消卸载。"
        exit 0
    fi

    print_msg "正在停止并移除 Systemd 服务..."
    systemctl stop sk5-monitor 2>/dev/null
    systemctl disable sk5-monitor 2>/dev/null
    rm -f /etc/systemd/system/sk5-monitor.service

    killall -9 danted 2>/dev/null
    systemctl disable $(systemctl list-unit-files | grep sk5-danted | awk '{print $1}') 2>/dev/null
    rm -f /etc/systemd/system/sk5-danted@.service
    systemctl daemon-reload

    print_msg "正在清理网络配置和 iptables 规则..."
    # 清理 iptables 规则
    iptables -D INPUT -j $MON_CHAIN 2>/dev/null
    iptables -F $MON_CHAIN 2>/dev/null
    iptables -X $MON_CHAIN 2>/dev/null

    # 尝试恢复网络状态 (如果有的话)
    if [[ -f "$IP_FILE" ]]; then
        while read -r line; do
            read -r ip port proto max remark <<< "$line"
            if [[ "$remark" == 虚拟IP* ]]; then
                ip addr del "$ip/24" dev "$MAIN_IF" 2>/dev/null
            elif [[ "$remark" == VLAN网卡* ]]; then
                # 根据之前生成的 vlan_id 尝试清理
                if [[ -f "$CONF_VLANS" ]]; then
                     local idx=1
                     while read -r v_line; do
                         [[ -z "$v_line" ]] && continue
                         read -r v_vip v_vlan_id v_mac <<< "$v_line"
                         local dev_name="vlan_${v_vlan_id}"
                         ip link delete "$dev_name" 2>/dev/null
                         local rt_table=$((100 + idx))
                         ip rule del from "$v_vip" table "$rt_table" 2>/dev/null
                         ((idx++))
                     done < "$CONF_VLANS"
                fi
            fi
        done < "$IP_FILE"
    fi

    print_msg "正在清理配置文件和程序目录..."
    rm -f /etc/danted-*.conf
    rm -rf $WORK_DIR
    apt-get remove -y dante-server > /dev/null 2>&1

    print_msg "卸载完成！"
    exit 0
}

# 主程序
clear
echo -e "${GREEN}======================================================${PLAIN}"
echo -e "${GREEN}       多IP Socks5 一键部署与流量控制脚本             ${PLAIN}"
echo -e "${GREEN}       支持系统: Ubuntu 18.04+ / Debian 11+           ${PLAIN}"
echo -e "${GREEN}======================================================${PLAIN}"
echo -e "  1. 安装并配置 Socks5 代理"
echo -e "  2. 卸载 Socks5 代理及配置"
echo -e "  0. 退出"
echo -e "${GREEN}======================================================${PLAIN}"
read -p "请输入选项 [0-2]: " choice

case "$choice" in
    1)
        check_root
        check_os
        get_main_network_info
        install_deps
        interactive_config
        setup_network
        setup_dante
        setup_traffic_monitor
        print_summary
        ;;
    2)
        check_root
        get_main_network_info
        uninstall
        ;;
    0)
        exit 0
        ;;
    *)
        print_err "无效的选项，已退出。"
        exit 1
        ;;
esac
