#!/bin/sh

set -eu

DEFAULT_PORT=22
SSH_PUB_KEY=""
SSH_PORT="$DEFAULT_PORT"
SSH_PUB_URL=""
DISABLE_PASS=0

usage() {
    printf "用法: %s -pub \"公钥内容\" [-url 公钥URL] [-port 端口] [-off]\n" "$0"
    printf "示例:\n"
    printf "  %s -pub \"ssh-ed25519 AAAAC3N...\" -port 2222\n" "$0"
    printf "  %s -url \"https://example.com/id_ed25519.pub\"\n" "$0"
    exit 1
}

# 参数解析
while [ $# -gt 0 ]; do
    case $1 in
        -pub)
            SSH_PUB_KEY="$2"
            shift 2
            ;;
        -url)
            SSH_PUB_URL="$2"
            shift 2
            ;;
        -port)
            SSH_PORT="$2"
            shift 2
            ;;
        -off)
            DISABLE_PASS=1
            shift 1
            ;;
        -h|--help)
            usage
            ;;
        *)
            printf "未知参数: %s\n" "$1"
            usage
            ;;
    esac
done

if [ -n "$SSH_PUB_URL" ]; then
    printf "从 URL 下载公钥: %s\n" "$SSH_PUB_URL"
    if command -v curl >/dev/null 2>&1; then
        SSH_PUB_KEY=$(curl -fsSL "$SSH_PUB_URL" 2>/dev/null || true)
    elif command -v wget >/dev/null 2>&1; then
        SSH_PUB_KEY=$(wget -qO- "$SSH_PUB_URL" 2>/dev/null || true)
    else
        printf "错误: 未找到 curl 或 wget\n"
        exit 1
    fi

    if [ -z "$SSH_PUB_KEY" ]; then
        printf "错误: 无法从 URL 获取公钥\n"
        exit 1
    fi
fi

if [ -z "$SSH_PUB_KEY" ]; then
    printf "错误: 必须提供公钥 (-pub 或 -url)\n"
    usage
fi

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    printf "需要 root 权限，正在提升...\n"
    if command -v sudo >/dev/null 2>&1; then
        exec sudo "$0" "$@"
    else
        printf "错误: 未找到 sudo 命令，请使用 root 用户运行\n"
        exit 1
    fi
fi

printf "开始配置 SSH...\n"

# 查找 sshd_config
SSHD_CONFIG=""
for config in /etc/ssh/sshd_config /etc/sshd_config; do
    if [ -f "$config" ]; then
        SSHD_CONFIG="$config"
        break
    fi
done

if [ -z "$SSHD_CONFIG" ]; then
    printf "错误: 未找到 sshd_config\n"
    exit 1
fi

# 备份
backup="$SSHD_CONFIG.backup.$(date +%s)"
cp "$SSHD_CONFIG" "$backup"
printf "已备份到: %s\n" "$backup"

configure_ssh() {
    # PermitRootLogin
    if grep -q "^PermitRootLogin" "$SSHD_CONFIG"; then
        sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' "$SSHD_CONFIG"
    else
        echo "PermitRootLogin yes" >> "$SSHD_CONFIG"
    fi

    # Port
    if grep -q "^Port" "$SSHD_CONFIG"; then
        sed -i "s/^Port.*/Port $SSH_PORT/" "$SSHD_CONFIG"
    else
        echo "Port $SSH_PORT" >> "$SSHD_CONFIG"
    fi

    # PubkeyAuthentication
    if ! grep -q "^PubkeyAuthentication yes" "$SSHD_CONFIG" 2>/dev/null; then
        if grep -q "^#\?PubkeyAuthentication" "$SSHD_CONFIG"; then
            sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
        else
            echo "PubkeyAuthentication yes" >> "$SSHD_CONFIG"
        fi
    fi

    # PasswordAuthentication
    if [ "$DISABLE_PASS" -eq 1 ]; then
        if grep -q "^#\?PasswordAuthentication" "$SSHD_CONFIG"; then
            sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
        else
            echo "PasswordAuthentication no" >> "$SSHD_CONFIG"
        fi
        printf "已禁用密码登录\n"
    else
        if grep -q "^#\?PasswordAuthentication" "$SSHD_CONFIG"; then
            sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
        else
            echo "PasswordAuthentication yes" >> "$SSHD_CONFIG"
        fi
    fi
}

setup_ssh_key() {
    if [ ! -d /root/.ssh ]; then
        mkdir -p /root/.ssh
    fi
    chmod 700 /root/.ssh

    if ! grep -Fxq "$SSH_PUB_KEY" /root/.ssh/authorized_keys 2>/dev/null; then
        printf "%s\n" "$SSH_PUB_KEY" >> /root/.ssh/authorized_keys
    fi

    chmod 600 /root/.ssh/authorized_keys
    chown root:root /root/.ssh/authorized_keys 2>/dev/null || chown root /root/.ssh/authorized_keys 2>/dev/null || true
}

restart_ssh() {
    # systemd (Debian, Ubuntu, Rocky, CentOS 等)
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
            printf "SSH 服务已重启 (systemd)\n"
            return 0
        fi
    fi
    
    # OpenRC (Alpine Linux)
    if command -v rc-service >/dev/null 2>&1; then
        if rc-service sshd restart 2>/dev/null || rc-service ssh restart 2>/dev/null; then
            printf "SSH 服务已重启 (OpenRC)\n"
            return 0
        fi
    fi

    if command -v service >/dev/null 2>&1; then
        if service sshd restart 2>/dev/null || service ssh restart 2>/dev/null; then
            printf "SSH 服务已重启 (SysV)\n"
            return 0
        fi
    fi
    
    printf "警告: 无法自动重启 SSH 服务，请手动重启。\n"
    return 1
}

configure_ssh
setup_ssh_key

if sshd -t 2>/dev/null; then
    printf "SSH 配置验证通过\n"
    restart_ssh
else
    printf "警告: 无法验证 SSH 配置，尝试重启服务...\n"
    restart_ssh || {
        printf "错误: SSH 配置可能有误，正在恢复备份...\n"
        cp "$backup" "$SSHD_CONFIG"
        exit 1
    }
fi

printf "\n配置完成:\n"
printf "root 登录: 已启用\n"
printf "SSH 端口: %s\n" "$SSH_PORT"
printf "公钥已写入: /root/.ssh/authorized_keys\n"
if [ "$DISABLE_PASS" -eq 1 ]; then
    printf "密码登录: 已禁用\n"
fi
