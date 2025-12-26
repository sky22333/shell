#!/bin/bash

# TPROXY 透明代理一键配置脚本
# 适用于 s-ui / 3x-ui 透明代理

set -e

# 默认配置参数
DEFAULT_TPROXY_PORT=12345   # 默认 TPROXY 监听端口
PROXY_FWMARK=1              # 防火墙标记
ROUTE_TABLE=100             # 策略路由表编号
CHAIN_NAME="XRAY_TPROXY"    # 自定义链名称

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 需要 root 权限${NC}"
        exit 1
    fi
}

get_tproxy_port() {
    echo -e "${GREEN}请输入 TPROXY 监听端口 [默认: $DEFAULT_TPROXY_PORT]:${NC}"
    read -p "> " input_port
    
    if [[ -z "$input_port" ]]; then
        TPROXY_PORT=$DEFAULT_TPROXY_PORT
    else
        if [[ "$input_port" =~ ^[0-9]+$ ]] && [ "$input_port" -ge 1 ] && [ "$input_port" -le 65535 ]; then
            TPROXY_PORT=$input_port
        else
            echo -e "${RED}错误: 无效端口号${NC}"
            return 1
        fi
    fi
    echo -e "${GREEN}使用端口: $TPROXY_PORT${NC}"
    echo ""
}

# 配置透明代理规则
setup_proxy() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}配置透明代理${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # 交互式获取端口
    get_tproxy_port || return
    
    # 创建自定义链
    iptables -t mangle -N $CHAIN_NAME 2>/dev/null || iptables -t mangle -F $CHAIN_NAME
    
    # 排除规则
    iptables -t mangle -A $CHAIN_NAME -d 127.0.0.0/8 -j RETURN
    iptables -t mangle -A $CHAIN_NAME -d 10.0.0.0/8 -j RETURN
    iptables -t mangle -A $CHAIN_NAME -d 172.16.0.0/12 -j RETURN
    iptables -t mangle -A $CHAIN_NAME -d 192.168.0.0/16 -j RETURN
    iptables -t mangle -A $CHAIN_NAME -d 169.254.0.0/16 -j RETURN
    iptables -t mangle -A $CHAIN_NAME -d 224.0.0.0/4 -j RETURN
    iptables -t mangle -A $CHAIN_NAME -d 255.255.255.255/32 -j RETURN
    
    # TPROXY 规则
    iptables -t mangle -A $CHAIN_NAME -p tcp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark $PROXY_FWMARK
    iptables -t mangle -A $CHAIN_NAME -p udp -j TPROXY --on-port $TPROXY_PORT --tproxy-mark $PROXY_FWMARK
    
    # 应用规则
    iptables -t mangle -A OUTPUT -j $CHAIN_NAME
    iptables -t mangle -A PREROUTING -j $CHAIN_NAME
    
    # 策略路由
    ip rule add fwmark $PROXY_FWMARK lookup $ROUTE_TABLE 2>/dev/null || true
    ip route add local 0.0.0.0/0 dev lo table $ROUTE_TABLE 2>/dev/null || true
    
    echo -e "${GREEN}配置完成！${NC}"
    echo -e "代理端口: ${YELLOW}$TPROXY_PORT${NC}"
    echo ""
    read -p "按回车键继续..."
}

# 移除透明代理规则
remove_proxy() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}移除透明代理规则${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    iptables -t mangle -D OUTPUT -j $CHAIN_NAME 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j $CHAIN_NAME 2>/dev/null || true
    iptables -t mangle -F $CHAIN_NAME 2>/dev/null || true
    iptables -t mangle -X $CHAIN_NAME 2>/dev/null || true
    
    ip rule del fwmark $PROXY_FWMARK lookup $ROUTE_TABLE 2>/dev/null || true
    ip route flush table $ROUTE_TABLE 2>/dev/null || true
    
    echo -e "${GREEN}规则已移除${NC}"
    echo ""
    read -p "按回车键继续..."
}

# 查看当前规则
show_rules() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}当前规则状态${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    echo -e "${BLUE}=== Mangle 表 ===${NC}"
    iptables -t mangle -L $CHAIN_NAME -v -n 2>/dev/null || echo "无规则"
    echo ""
    
    echo -e "${BLUE}=== 策略路由 ===${NC}"
    ip rule show | grep "fwmark $PROXY_FWMARK" || echo "无规则"
    echo ""
    
    echo -e "${BLUE}=== 路由表 ===${NC}"
    ip route show table $ROUTE_TABLE 2>/dev/null || echo "无规则"
    echo ""
    
    read -p "按回车键继续..."
}

# 保存规则
save_rules() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}保存规则${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    # 保存 iptables
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
    echo -e "${GREEN}✓ iptables 规则已保存${NC}"
    
    # 创建 systemd 服务
    cat > /etc/systemd/system/tproxy-route.service << EOF
[Unit]
Description=TPROXY Policy Routing
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'ip rule add fwmark $PROXY_FWMARK lookup $ROUTE_TABLE 2>/dev/null || true; ip route add local 0.0.0.0/0 dev lo table $ROUTE_TABLE 2>/dev/null || true'
ExecStop=/bin/bash -c 'ip rule del fwmark $PROXY_FWMARK lookup $ROUTE_TABLE 2>/dev/null || true; ip route flush table $ROUTE_TABLE 2>/dev/null || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable tproxy-route.service >/dev/null 2>&1
    echo -e "${GREEN}✓ systemd 服务已创建${NC}"
    echo -e "${GREEN}✓ 开机自动恢复已启用${NC}"
    echo ""
    read -p "按回车键继续..."
}

show_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   TPROXY 透明代理配置工具${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} 配置透明代理"
    echo -e "${GREEN}2.${NC} 移除透明代理"
    echo -e "${GREEN}3.${NC} 查看当前状态"
    echo -e "${GREEN}4.${NC} 保存规则（持久化）"
    echo -e "${RED}0.${NC} 退出"
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

main() {
    check_root
    
    while true; do
        show_menu
        read -p "请选择操作 [0-4]: " choice
        echo ""
        
        case $choice in
            1)
                setup_proxy
                ;;
            2)
                remove_proxy
                ;;
            3)
                show_rules
                ;;
            4)
                save_rules
                ;;
            0)
                echo -e "${GREEN}退出程序${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请重新选择${NC}"
                sleep 2
                ;;
        esac
    done
}

main
