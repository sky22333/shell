#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

CONFIG_DIR="${HOME}/.openclaw"
CONFIG_FILE="${CONFIG_DIR}/openclaw.json"
PLIST_LABEL="com.openclaw.gateway"
PLIST_PATH="${HOME}/Library/LaunchAgents/${PLIST_LABEL}.plist"
LOG_DIR="${HOME}/Library/Logs/openclaw"
LOG_FILE="${LOG_DIR}/gateway.log"
ERR_FILE="${LOG_DIR}/gateway.error.log"

log_info() {
    echo -e "${GREEN}[INFO] $1${PLAIN}"
}

log_warn() {
    echo -e "${YELLOW}[WARN] $1${PLAIN}"
}

log_error() {
    echo -e "${RED}[ERROR] $1${PLAIN}"
}

check_macos() {
    if [ "$(uname -s)" != "Darwin" ]; then
        log_error "此脚本仅支持 macOS。"
        exit 1
    fi
}

ensure_brew() {
    if command -v brew >/dev/null 2>&1; then
        return
    fi
    log_warn "未检测到 Homebrew，需要先安装。"
    read -p "是否安装 Homebrew？[y/n]: " install_brew
    if [ "$install_brew" != "y" ]; then
        log_error "已取消 Homebrew 安装。"
        exit 1
    fi
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [ -x "/opt/homebrew/bin/brew" ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x "/usr/local/bin/brew" ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    if ! command -v brew >/dev/null 2>&1; then
        log_error "Homebrew 安装失败，请检查网络。"
        exit 1
    fi
}

install_nodejs() {
    log_info "正在检查 Node.js 环境..."
    if command -v node >/dev/null 2>&1; then
        NODE_VERSION_FULL=$(node -v)
        NODE_MAJOR=$(echo "$NODE_VERSION_FULL" | cut -d'v' -f2 | cut -d'.' -f1)
        if [ "$NODE_MAJOR" -ge 22 ]; then
            log_info "Node.js 已安装且版本符合要求 (${NODE_VERSION_FULL})，无需重复安装。"
            return
        fi
        log_warn "检测到旧版本 Node.js (${NODE_VERSION_FULL})，即将自动升级到 22.x。"
    fi
    ensure_brew
    log_info "正在安装 Node.js 22..."
    brew install node@22
    brew link --force --overwrite node@22
    if command -v node >/dev/null 2>&1; then
        NODE_VERSION=$(node -v)
        log_info "Node.js 安装成功: ${NODE_VERSION}"
    else
        log_error "Node.js 安装失败，请检查网络或系统源。"
        exit 1
    fi
}

install_git() {
    log_info "正在检查 Git 环境..."
    if command -v git >/dev/null 2>&1; then
        log_info "Git 已安装，无需重复安装。"
        return
    fi
    ensure_brew
    log_info "正在安装 Git..."
    brew install git
    if command -v git >/dev/null 2>&1; then
        GIT_VERSION=$(git --version)
        log_info "Git 安装成功: ${GIT_VERSION}"
    else
        log_error "Git 安装失败，请检查网络或系统源。"
        exit 1
    fi
}

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
        log_error "OpenClaw 安装失败，请检查 npm 权限或网络。"
        exit 1
    fi
}

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
    
    # 生成随机 Token
    if command -v openssl >/dev/null 2>&1; then
        GATEWAY_TOKEN=$(openssl rand -hex 16)
    else
        GATEWAY_TOKEN=$(date +%s%N | sha256sum | head -c 32)
    fi

    echo -e "${CYAN}请选择 API 类型:${PLAIN}"
    echo "1. Anthropic 官方 API"
    echo "2. OpenAI 兼容 API (中转站/其他模型)"
    read -p "请输入选项 [1/2]: " api_choice
    read -p "是否配置 Telegram 机器人？[y/n]: " enable_telegram
    if [ "$enable_telegram" == "y" ]; then
        read -p "请输入 Telegram Bot Token: " bot_token
        read -p "请输入您的 Telegram User ID (用于管理员白名单): " admin_id
    else
        log_warn "已跳过 Telegram 机器人配置。"
    fi
    if [ "$api_choice" == "1" ]; then
        read -p "请输入 Anthropic API Key (sk-ant-...): " api_key
        if [ "$enable_telegram" == "y" ]; then
            cat > "${CONFIG_FILE}" <<EOF
{
  "gateway": {
    "mode": "local",
    "bind": "loopback",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "${GATEWAY_TOKEN}"
    }
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
            cat > "${CONFIG_FILE}" <<EOF
{
  "gateway": {
    "mode": "local",
    "bind": "loopback",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "${GATEWAY_TOKEN}"
    }
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
      "enabled": false
    },
    "allow": ["exec", "process", "read", "write", "edit", "web_search", "web_fetch", "cron"]
  },
  "channels": {
    "telegram": {
      "enabled": false
    }
  }
}
EOF
        fi
    else
        read -p "请输入 API Base URL (例如 https://example.com/v1): " base_url
        read -p "请输入 API Key (例如 sk-abc123...): " api_key
        read -p "请输入模型名称 (例如 gpt-4o): " model_name
        if [ "$enable_telegram" == "y" ]; then
            cat > "${CONFIG_FILE}" <<EOF
{
  "gateway": {
    "mode": "local",
    "bind": "loopback",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "${GATEWAY_TOKEN}"
    }
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
        else
            cat > "${CONFIG_FILE}" <<EOF
{
  "gateway": {
    "mode": "local",
    "bind": "loopback",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "${GATEWAY_TOKEN}"
    }
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
      "enabled": false
    },
    "allow": ["exec", "process", "read", "write", "edit", "web_search", "web_fetch", "cron"]
  },
  "channels": {
    "telegram": {
      "enabled": false
    }
  }
}
EOF
        fi
    fi
    log_info "配置文件已生成: ${CONFIG_FILE}"
    echo -e "${GREEN}配置文件绝对路径: ${CONFIG_FILE}${PLAIN}"
    echo -e "${GREEN}Gateway Token: ${GATEWAY_TOKEN}${PLAIN}"
    echo -e "${YELLOW}请妥善保存此 Token，用于远程连接 Gateway。${PLAIN}"
}

setup_launchd() {
    log_info "正在配置 LaunchAgent 服务..."
    mkdir -p "$(dirname "${PLIST_PATH}")"
    mkdir -p "${LOG_DIR}"
    GATEWAY_BIN=$(command -v openclaw)
    if [ -z "${GATEWAY_BIN}" ]; then
        log_error "未找到 openclaw 可执行文件。"
        exit 1
    fi
    NODE_BIN=$(command -v node)
    if [ -z "${NODE_BIN}" ]; then
        log_error "未找到 node 可执行文件。"
        exit 1
    fi
    NODE_DIR=$(dirname "${NODE_BIN}")
    LAUNCH_PATH="${NODE_DIR}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    cat > "${PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${PLIST_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${NODE_BIN}</string>
    <string>${GATEWAY_BIN}</string>
    <string>gateway</string>
    <string>--verbose</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${LOG_FILE}</string>
  <key>StandardErrorPath</key>
  <string>${ERR_FILE}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>${HOME}</string>
    <key>PATH</key>
    <string>${LAUNCH_PATH}</string>
  </dict>
</dict>
</plist>
EOF
    launchctl bootout "gui/${UID}" "${PLIST_PATH}" >/dev/null 2>&1
    launchctl bootstrap "gui/${UID}" "${PLIST_PATH}"
    launchctl kickstart -k "gui/${UID}/${PLIST_LABEL}" >/dev/null 2>&1
    log_info "服务已启动并设置开机自启。"
}

service_start() {
    launchctl bootstrap "gui/${UID}" "${PLIST_PATH}" >/dev/null 2>&1
    launchctl kickstart -k "gui/${UID}/${PLIST_LABEL}" >/dev/null 2>&1
    log_info "服务已启动"
}

service_stop() {
    launchctl bootout "gui/${UID}" "${PLIST_PATH}" >/dev/null 2>&1
    log_info "服务已停止"
}

service_restart() {
    service_stop
    service_start
}

service_status() {
    launchctl print "gui/${UID}/${PLIST_LABEL}"
}

service_logs() {
    if [ -f "${LOG_FILE}" ] || [ -f "${ERR_FILE}" ]; then
        tail -f "${LOG_FILE}" "${ERR_FILE}"
    else
        log_warn "暂无日志文件，请先启动服务。"
    fi
}

install() {
    check_macos
    install_git
    install_nodejs
    install_openclaw_core
    configure_openclaw
    setup_launchd
    echo -e "${GREEN}=============================================${PLAIN}"
    echo -e "${GREEN} OpenClaw 安装配置完成！${PLAIN}"
    echo -e "${GREEN}=============================================${PLAIN}"
    echo -e "请等待OpenClaw初始化完成（约1分钟），然后使用Telegram向您的Bot发送消息开始使用。"
    echo -e "${GREEN}=============================================${PLAIN}"
}

uninstall() {
    check_macos
    read -p "确定要卸载 OpenClaw 吗？配置文件也将被删除 [y/n]: " confirm
    if [ "$confirm" != "y" ]; then
        echo "已取消。"
        return
    fi
    service_stop
    rm -f "${PLIST_PATH}"
    npm uninstall -g openclaw
    npm uninstall -g clawdbot
    rm -rf "${CONFIG_DIR}"
    log_info "OpenClaw 已卸载。"
}

modify_config() {
    echo -e "${YELLOW}注意：此操作将重新生成配置文件，并且重启服务。${PLAIN}"
    configure_openclaw
    log_info "正在重启服务以应用更改..."
    service_restart
}

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
        2) service_start ;;
        3) service_stop ;;
        4) service_restart ;;
        5) service_status ;;
        6) service_logs ;;
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
