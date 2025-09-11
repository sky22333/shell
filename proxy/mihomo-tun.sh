#!/bin/bash
set -e

# mihomo 版本号
MIHOMO_VERSION="${MIHOMO_VERSION:-1.19.11}"

CONFIG_DIR="/etc/mihomo"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
SERVICE_FILE="/etc/systemd/system/mihomo.service"
BINARY_PATH="/usr/local/bin/mihomo"

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
    
    # 检查 gzip
    if ! command -v gzip &>/dev/null; then
        echo "gzip 未安装，正在安装..."
        if command -v apt-get &>/dev/null; then
            apt-get update && apt-get install -y gzip
        elif command -v yum &>/dev/null; then
            yum install -y gzip
        elif command -v dnf &>/dev/null; then
            dnf install -y gzip
        elif command -v pacman &>/dev/null; then
            pacman -S --noconfirm gzip
        else
            echo "无法自动安装 gzip，请手动安装后重试"
            exit 1
        fi
    fi
    
    echo "依赖检查完成"
}

# 安装 mihomo
install_mihomo() {
    check_dependencies
    
    if ! command -v mihomo &>/dev/null; then
        echo "检测到 mihomo 未安装，正在下载..."
        
        # 获取系统架构
        ARCH=$(uname -m)
        case "$ARCH" in
            x86_64)
                ARCH_TAG="linux-amd64"
                ;;
            aarch64 | arm64)
                ARCH_TAG="linux-arm64"
                ;;
            armv7l)
                ARCH_TAG="linux-armv7"
                ;;
            *)
                echo "不支持的架构: $ARCH"
                exit 1
                ;;
        esac

        # 下载地址
        DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/v${MIHOMO_VERSION}/mihomo-${ARCH_TAG}-v${MIHOMO_VERSION}.gz"
        
        echo "正在从以下地址下载: $DOWNLOAD_URL"
        
        # 下载并解压二进制文件
        if curl -L -o "/tmp/mihomo.gz" "$DOWNLOAD_URL"; then
            gzip -d "/tmp/mihomo.gz"
            mv "/tmp/mihomo" "$BINARY_PATH"
            chmod +x "$BINARY_PATH"
            echo "mihomo ${MIHOMO_VERSION} 安装完成 ($ARCH)"
        else
            echo "下载失败，请检查网络连接或版本号"
            exit 1
        fi
    else
        echo "mihomo 已安装"
    fi
}

# 配置 mihomo
configure_mihomo() {
    mkdir -p "$CONFIG_DIR"
    
    # 获取 SOCKS5 代理配置
    read -rp "请输入SOCKS5代理服务器地址 [默认127.0.0.1]: " SOCKS_ADDRESS
    SOCKS_ADDRESS=${SOCKS_ADDRESS:-127.0.0.1}
    read -rp "请输入SOCKS5代理服务器端口 [默认7890]: " SOCKS_PORT
    SOCKS_PORT=${SOCKS_PORT:-7890}

    cat > "$CONFIG_FILE" <<EOF
allow-lan: false
mode: rule
log-level: info

tun:
  enable: true
  stack: system
  auto-route: true
  auto-detect-interface: true

dns:
  enable: true
  listen: 0.0.0.0:53
  enhanced-mode: fake-ip
  nameserver:
    - 8.8.8.8
    - 1.1.1.1

proxies:
  - name: socks5-out
    type: socks5
    server: $SOCKS_ADDRESS
    port: $SOCKS_PORT
    udp: true

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - socks5-out

rules:
  - MATCH,PROXY
EOF
    echo "配置文件生成完成: $CONFIG_FILE"
}

# 创建 systemd 服务
create_systemd_service() {
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=mihomo Daemon, Another Clash Kernel.
After=network.target NetworkManager.service systemd-networkd.service iwd.service

[Service]
Type=simple
LimitNPROC=500
LimitNOFILE=1000000
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
Restart=always
ExecStartPre=/usr/bin/sleep 1s
ExecStart=$BINARY_PATH -d $CONFIG_DIR
ExecReload=/bin/kill -HUP \$MAINPID

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable mihomo.service
    echo "systemd 服务创建完成并已设置开机自启"
}

# 菜单操作
menu() {
    while true; do
        echo "===================================="
        echo " mihomo 管理脚本"
        echo " 当前版本: $MIHOMO_VERSION"
        echo "===================================="
        echo "1) 安装 & 配置 mihomo (自动启动)"
        echo "3) 停止服务"
        echo "4) 重启服务"
        echo "5) 查看状态"
        echo "6) 卸载服务"
        echo "0) 退出"
        echo "===================================="
        read -rp "请选择操作: " choice
        case "$choice" in
            1)
                install_mihomo
                configure_mihomo
                create_systemd_service
                systemctl start mihomo.service
                echo "mihomo 已安装并启动"
                ;;
            3)
                systemctl stop mihomo.service
                echo "服务已停止"
                ;;
            4)
                systemctl restart mihomo.service
                echo "服务已重启"
                ;;
            5)
                systemctl status mihomo.service
                ;;
            6)
                systemctl stop mihomo.service || true
                systemctl disable mihomo.service || true
                
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
