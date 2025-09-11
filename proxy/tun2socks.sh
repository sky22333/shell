#!/bin/bash
set -e

# 全局环境变量 - tun2socks 版本
TUN2SOCKS_VERSION="${TUN2SOCKS_VERSION:-2.13.0}"

CONFIG_DIR="/etc/tun2socks"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
SERVICE_FILE="/etc/systemd/system/tun2socks.service"
BINARY_PATH="/usr/local/bin/hev-socks5-tunnel"

# 检查 root
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 运行脚本"
    exit 1
fi

# 检查并安装依赖
check_dependencies() {
    echo "检查系统依赖..."
    
    # 检查 curl
    if ! command -v curl &>/dev/null; then
        echo "curl 未安装，正在安装..."
        if command -v apt-get &>/dev/null; then
            apt-get update && apt-get install -y curl
        elif command -v yum &>/dev/null; then
            yum install -y curl
        elif command -v dnf &>/dev/null; then
            dnf install -y curl
        elif command -v pacman &>/dev/null; then
            pacman -S --noconfirm curl
        else
            echo "无法自动安装 curl，请手动安装后重试"
            exit 1
        fi
    fi
    
    # 检查 unzip
    if ! command -v unzip &>/dev/null; then
        echo "unzip 未安装，正在安装..."
        if command -v apt-get &>/dev/null; then
            apt-get update && apt-get install -y unzip
        elif command -v yum &>/dev/null; then
            yum install -y unzip
        elif command -v dnf &>/dev/null; then
            dnf install -y unzip
        elif command -v pacman &>/dev/null; then
            pacman -S --noconfirm unzip
        else
            echo "无法自动安装 unzip，请手动安装后重试"
            exit 1
        fi
    fi
    
    echo "依赖检查完成"
}

# 安装 tun2socks
install_tun2socks() {
    # 首先检查依赖
    check_dependencies
    
    if ! command -v hev-socks5-tunnel &>/dev/null; then
        echo "检测到 hev-socks5-tunnel 未安装，正在下载..."
        
        # 获取系统架构
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64)
                ARCH_TAG="linux-x86_64"
                ;;
            aarch64 | arm64)
                ARCH_TAG="linux-arm64"
                ;;
            armv7l)
                ARCH_TAG="linux-arm32v7"
                ;;
            *)
                echo "不支持的架构: $ARCH"
                exit 1
                ;;
        esac

        # 直链下载地址
        DOWNLOAD_URL="https://github.com/heiher/hev-socks5-tunnel/releases/download/${TUN2SOCKS_VERSION}/hev-socks5-tunnel-${ARCH_TAG}"
        
        echo "正在从以下地址下载: $DOWNLOAD_URL"
        
        # 下载二进制文件
        if curl -L -o "$BINARY_PATH" "$DOWNLOAD_URL"; then
            chmod +x "$BINARY_PATH"
            echo "hev-socks5-tunnel ${TUN2SOCKS_VERSION} 安装完成 ($ARCH)"
        else
            echo "下载失败，请检查网络连接或版本号"
            exit 1
        fi
    else
        echo "hev-socks5-tunnel 已安装"
    fi
}

# 配置 Socks5
configure_tun2socks() {
    mkdir -p "$CONFIG_DIR"
    read -rp "请输入Socks5服务器地址 [默认127.0.0.1]: " SOCKS_ADDRESS
    SOCKS_ADDRESS=${SOCKS_ADDRESS:-127.0.0.1}
    read -rp "请输入Socks5服务器端口 [默认7890]: " SOCKS_PORT
    SOCKS_PORT=${SOCKS_PORT:-7890}

    cat > "$CONFIG_FILE" <<EOF
tunnel:
  name: tun0
  mtu: 8500
  multi-queue: true
  ipv4: 198.18.0.1

socks5:
  address: '$SOCKS_ADDRESS'
  port: $SOCKS_PORT
  udp: 'udp'
  mark: 438
EOF
    echo "配置文件生成完成: $CONFIG_FILE"
}

# 创建 systemd 服务
create_systemd_service() {
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Tun2Socks Tunnel Service
After=network.target

[Service]
Type=simple
ExecStart=$BINARY_PATH $CONFIG_FILE
ExecStartPost=/bin/sleep 1
ExecStartPost=/sbin/ip rule add fwmark 438 lookup main pref 10
ExecStartPost=/sbin/ip -6 rule add fwmark 438 lookup main pref 10
ExecStartPost=/sbin/ip route add default dev tun0 table 20
ExecStartPost=/sbin/ip rule add lookup 20 pref 20
ExecStartPost=/sbin/ip rule add to 127.0.0.0/8 lookup main pref 16
ExecStartPost=/sbin/ip rule add to 10.0.0.0/8 lookup main pref 16
ExecStartPost=/sbin/ip rule add to 172.16.0.0/12 lookup main pref 16
ExecStartPost=/sbin/ip rule add to 192.168.0.0/16 lookup main pref 16

ExecStop=/sbin/ip rule del fwmark 438 lookup main pref 10 || true
ExecStop=/sbin/ip -6 rule del fwmark 438 lookup main pref 10 || true
ExecStop=/sbin/ip route del default dev tun0 table 20 || true
ExecStop=/sbin/ip rule del lookup 20 pref 20 || true
ExecStop=/sbin/ip rule del to 127.0.0.0/8 lookup main pref 16 || true
ExecStop=/sbin/ip rule del to 10.0.0.0/8 lookup main pref 16 || true
ExecStop=/sbin/ip rule del to 172.16.0.0/12 lookup main pref 16 || true
ExecStop=/sbin/ip rule del to 192.168.0.0/16 lookup main pref 16 || true

Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable tun2socks.service
    echo "systemd 服务创建完成并已设置开机自启"
}

# 菜单操作
menu() {
    while true; do
        echo "===================================="
        echo " socks5-tun 管理脚本"
        echo " 当前版本: $TUN2SOCKS_VERSION"
        echo "===================================="
        echo "1) 安装 & 配置 socks5-tun"
        echo "2) 启动服务"
        echo "3) 停止服务"
        echo "4) 重启服务"
        echo "5) 查看状态"
        echo "6) 卸载服务"
        echo "0) 退出"
        echo "===================================="
        read -rp "请选择操作: " choice
        case "$choice" in
            1)
                install_tun2socks
                configure_tun2socks
                create_systemd_service
                systemctl start tun2socks.service
                echo "hev-socks5-tunnel 已启动"
                ;;
            2)
                systemctl start tun2socks.service
                echo "服务已启动"
                ;;
            3)
                systemctl stop tun2socks.service
                echo "服务已停止"
                ;;
            4)
                systemctl restart tun2socks.service
                echo "服务已重启"
                ;;
            5)
                systemctl status tun2socks.service
                ;;
            6)
                systemctl stop tun2socks.service || true
                systemctl disable tun2socks.service || true
                
                # 清理残留的路由规则
                echo "正在清理路由规则..."
                ip rule del fwmark 438 lookup main pref 10 2>/dev/null || true
                ip -6 rule del fwmark 438 lookup main pref 10 2>/dev/null || true
                ip route del default dev tun0 table 20 2>/dev/null || true
                ip rule del lookup 20 pref 20 2>/dev/null || true
                ip rule del to 127.0.0.0/8 lookup main pref 16 2>/dev/null || true
                ip rule del to 10.0.0.0/8 lookup main pref 16 2>/dev/null || true
                ip rule del to 172.16.0.0/12 lookup main pref 16 2>/dev/null || true
                ip rule del to 192.168.0.0/16 lookup main pref 16 2>/dev/null || true
                
                while ip rule del pref 15 2>/dev/null; do
                    echo "删除了一条优先级为15的规则"
                done
                
                rm -f "$SERVICE_FILE"
                rm -rf "$CONFIG_DIR"
                rm -f "$BINARY_PATH"
                systemctl daemon-reload
                echo "服务已卸载"
                ;;
            0)
                exit 0
                ;;
            *)
                echo "无效选择"
                ;;
        esac
    done
}

menu
