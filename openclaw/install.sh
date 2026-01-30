#!/bin/bash

# OpenClaw 一键安装与管理脚本
# 兼容 Debian / Ubuntu / CentOS / RHEL / Fedora / AlmaLinux / Rocky Linux / Oracle Linux
# 官方文档: https://openclaw.ai/

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# 配置文件路径
# OpenClaw 使用 .openclaw 目录
CONFIG_DIR="${HOME}/.openclaw"
CONFIG_FILE="${CONFIG_DIR}/openclaw.json"
SERVICE_FILE="/etc/systemd/system/openclaw.service"

check_root() {
    if [ $EUID -ne 0 ]; then
        echo -e "${RED}错误: 请使用 root 用户运行此脚本！${PLAIN}"
        exit 1
    fi
}

check_sys() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            debian|ubuntu|kali)
                PM="apt-get"
                NODE_REPO="https://deb.nodesource.com/setup_22.x"
                ;;
            centos|rhel|fedora|almalinux|rocky|ol)
                PM="yum"
                command -v dnf >/dev/null 2>&1 && PM="dnf"
                NODE_REPO="https://rpm.nodesource.com/setup_22.x"
                ;;
            *)
                echo -e "${RED}错误: 本脚本不支持当前系统: $ID${PLAIN}"
                exit 1
                ;;
        esac
    else
        echo -e "${RED}错误: 无法检测系统版本！${PLAIN}"
        exit 1
    fi
}

log_info() {
    echo -e "${GREEN}[INFO] $1${PLAIN}"
}

log_warn() {
    echo -e "${YELLOW}[WARN] $1${PLAIN}"
}

log_error() {
    echo -e "${RED}[ERROR] $1${PLAIN}"
}

# 安装 Node.js 22+
install_nodejs() {
    log_info "正在检查 Node.js 环境..."
    
    if command -v node >/dev/null 2>&1; then
        NODE_VERSION_FULL=$(node -v)
        NODE_MAJOR=$(echo "$NODE_VERSION_FULL" | cut -d'v' -f2 | cut -d'.' -f1)
        
        if [ "$NODE_MAJOR" -ge 22 ]; then
            log_info "Node.js 已安装且版本符合要求 (${NODE_VERSION_FULL})，无需重复安装。"
            return
        else
            log_warn "检测到旧版本 Node.js (${NODE_VERSION_FULL})，OpenClaw 需要 Node.js 22+"
            read -p "是否升级 Node.js 到 22.x？(这将覆盖现有版本) [y/n]: " upgrade_node
            if [ "$upgrade_node" != "y" ]; then
                log_error "已取消 Node.js 升级。OpenClaw 可能无法正常运行。"
                return
            fi
        fi
    fi

    log_info "正在安装Node.js"
    if [ "$PM" == "apt-get" ]; then
        [ -d /etc/apt/sources.list.d ] || mkdir -p /etc/apt/sources.list.d
    fi
    
    $PM install -y curl git
    curl -fsSL $NODE_REPO | bash -
    $PM install -y nodejs
    
    if command -v node >/dev/null 2>&1; then
        NODE_VERSION=$(node -v)
        log_info "Node.js 安装成功: ${NODE_VERSION}"
    else
        log_error "Node.js 安装失败，请检查网络或系统源！"
        exit 1
    fi
}

# 安装 OpenClaw
install_openclaw_core() {
    log_info "正在安装 OpenClaw..."
    
    if command -v openclaw >/dev/null 2>&1; then
        CURRENT_VERSION=$(openclaw --version)
        log_warn "OpenClaw 已安装 (版本: ${CURRENT_VERSION})"
        read -p "是否强制重新安装/更新？[y/n]: " force_install
        if [ "$force_install" != "y" ]; then
            log_info "跳过安装步骤。"
            return
        fi
    fi
    
    npm install -g openclaw@latest
    
    if command -v openclaw >/dev/null 2>&1; then
        VERSION=$(openclaw --version)
        log_info "OpenClaw 安装成功，版本: ${VERSION}"
    else
        log_error "OpenClaw 安装失败，请检查 npm 权限或网络！"
        exit 1
    fi
}

# 配置 OpenClaw
configure_openclaw() {
    if [ -f "${CONFIG_FILE}" ]; then
        log_warn "检测到已存在配置文件: ${CONFIG_FILE}"
        read -p "是否覆盖现有配置？[y/n]: " overwrite_config
        if [ "$overwrite_config" != "y" ]; then
            log_info "保留现有配置，跳过配置步骤。"
            return
        fi
    fi

    log_info "开始配置 OpenClaw..."
    
    mkdir -p "${CONFIG_DIR}"
    
    echo -e "${CYAN}请选择 API 类型:${PLAIN}"
    echo "1. Anthropic 官方 API"
    echo "2. OpenAI 兼容 API (中转站/其他模型)"
    read -p "请输入选项 [1/2]: " api_choice

    read -p "请输入 Telegram Bot Token: " bot_token
    read -p "请输入您的 Telegram User ID (用于管理员白名单): " admin_id

    if [ "$api_choice" == "1" ]; then
        read -p "请输入 Anthropic API Key (sk-ant-...): " api_key
        
        cat > "${CONFIG_FILE}" <<EOF
{
  "gateway": {
    "mode": "local",
    "bind": "loopback",
    "port": 18789
  },
  "env": {
    "ANTHROPIC_API_KEY": "${api_key}"
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-5-20261022"
      }
    }
  },
  "tools": {
    "elevated": {
      "enabled": true,
      "allowFrom": {
        "telegram": ["${admin_id}"]
      }
    },
    "allow": ["exec", "process", "read", "write", "edit", "web_search", "web_fetch", "cron"]
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "${bot_token}",
      "dmPolicy": "pairing",
      "allowFrom": ["${admin_id}"]
    }
  }
}
EOF
    else
        read -p "请输入 API Base URL (例如 https://example.com/v1): " base_url
        read -p "请输入 API Key (例如 sk-abc123...): " api_key
        read -p "请输入模型名称 (例如 gpt-4o): " model_name
        
        cat > "${CONFIG_FILE}" <<EOF
{
  "gateway": {
    "mode": "local",
    "bind": "loopback",
    "port": 18789
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "openai-compat/${model_name}"
      },
      "elevatedDefault": "full",
      "compaction": {
        "mode": "safeguard"
      },
      "maxConcurrent": 4
    }
  },
  "models": {
    "mode": "merge",
    "providers": {
      "openai-compat": {
        "baseUrl": "${base_url}",
        "apiKey": "${api_key}",
        "api": "openai-completions",
        "models": [
          {
            "id": "${model_name}",
            "name": "${model_name}"
          }
        ]
      }
    }
  },
  "tools": {
    "exec": {
      "backgroundMs": 10000,
      "timeoutSec": 1800,
      "cleanupMs": 1800000,
      "notifyOnExit": true
    },
    "elevated": {
      "enabled": true,
      "allowFrom": {
        "telegram": ["${admin_id}"]
      }
    },
    "allow": ["exec", "process", "read", "write", "edit", "web_search", "web_fetch", "cron"]
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "${bot_token}",
      "dmPolicy": "pairing",
      "allowFrom": ["${admin_id}"]
    }
  }
}
EOF
    fi
    
    log_info "配置文件已生成: ${CONFIG_FILE}"
}

# 配置 Systemd 服务
setup_systemd() {
    log_info "正在配置 Systemd 服务..."
    
    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=OpenClaw Gateway
After=network.target

[Service]
Type=simple
User=root
ExecStart=$(command -v openclaw) gateway --verbose
Restart=always
RestartSec=5
Environment=HOME=${HOME}

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable openclaw
    systemctl restart openclaw
    
    log_info "服务已启动并设置开机自启！"
}

# 安装流程
install() {
    check_root
    check_sys
    install_nodejs
    install_openclaw_core
    configure_openclaw
    setup_systemd
    
    echo -e "${GREEN}=============================================${PLAIN}"
    echo -e "${GREEN} OpenClaw 安装配置完成！${PLAIN}"
    echo -e "${GREEN}=============================================${PLAIN}"
    echo -e "请等待OpenClaw初始化完成（约1分钟），然后使用Telegram向您的Bot发送消息开始使用。"
    echo -e "${GREEN}=============================================${PLAIN}"
}

# 卸载流程
uninstall() {
    check_root
    read -p "确定要卸载 OpenClaw 吗？配置文件也将被删除 [y/n]: " confirm
    if [ "$confirm" != "y" ]; then
        echo "已取消。"
        return
    fi
    
    systemctl stop openclaw
    systemctl disable openclaw
    rm -f "${SERVICE_FILE}"
    systemctl daemon-reload
    
    npm uninstall -g openclaw
    npm uninstall -g clawdbot
    rm -rf "${CONFIG_DIR}"
    
    log_info "OpenClaw 已卸载。"
}

# 修改配置 (重新运行配置向导)
modify_config() {
    echo -e "${YELLOW}注意：此操作将重新生成配置文件，并且重启服务。${PLAIN}"
    configure_openclaw
    log_info "正在重启服务以应用更改..."
    systemctl restart openclaw
    sleep 1
    if systemctl is-active --quiet openclaw; then
        log_info "服务已重启并正常运行。"
    else
        log_error "服务启动失败！请查看日志。"
    fi
}

# 菜单
show_menu() {
    clear
    echo -e "${CYAN}OpenClaw （原ClawdBot）管理脚本${PLAIN}"
    echo -e "${CYAN}------------------------${PLAIN}"
    echo -e "1. 安装并配置 OpenClaw"
    echo -e "2. 启动服务"
    echo -e "3. 停止服务"
    echo -e "4. 重启服务"
    echo -e "5. 查看运行状态"
    echo -e "6. 查看实时日志"
    echo -e "7. 修改配置文件"
    echo -e "8. 卸载 OpenClaw"
    echo -e "9. 运行doctor自检"
    echo -e "0. 退出脚本"
    echo -e "${CYAN}------------------------${PLAIN}"
    read -p "请输入选项 [0-9]: " choice
    
    case "$choice" in
        1) install ;;
        2) systemctl start openclaw && log_info "服务已启动" ;;
        3) systemctl stop openclaw && log_info "服务已停止" ;;
        4) systemctl restart openclaw && log_info "服务已重启" ;;
        5) systemctl status openclaw ;;
        6) journalctl -u openclaw -f ;;
        7) modify_config ;;
        8) uninstall ;;
        9) openclaw doctor ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选项，请重新输入${PLAIN}" ;;
    esac
}

if [ $# -gt 0 ]; then
    case "$1" in
        install) install ;;
        uninstall) uninstall ;;
        *) echo "用法: $0 [install|uninstall] 或直接运行进入菜单" ;;
    esac
else
    while true; do
        show_menu
        echo -e "\n按回车键继续..."
        read
    done
fi
