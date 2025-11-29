#!/bin/bash

set -euo pipefail

DEFAULT_PORT=22
SSH_PUB_KEY=""
SSH_PORT="$DEFAULT_PORT"
SSH_PUB_URL=""
DISABLE_PASS=0

usage() {
    echo "用法: $0 -pub \"公钥内容\" [-url 公钥URL] [-port 端口] [-off]"
    echo "示例:"
    echo "  $0 -pub \"ssh-ed25519 AAAAC3N...\" -port 2222"
    echo "  $0 -url \"https://example.com/id_ed25519.pub\""
    exit 1
}

# 参数解析
while [[ $# -gt 0 ]]; do
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
            echo "未知参数: $1"
            usage
            ;;
    esac
done

if [[ -n "$SSH_PUB_URL" ]]; then
    echo "从 URL 下载公钥: $SSH_PUB_URL"
    SSH_PUB_KEY=$(curl -fsSL "$SSH_PUB_URL" || true)

    if [[ -z "$SSH_PUB_KEY" ]]; then
        echo "错误: 无法从 URL 获取公钥"
        exit 1
    fi
fi

if [[ -z "$SSH_PUB_KEY" ]]; then
    echo "错误: 必须提供公钥 (-pub 或 -url)"
    usage
fi

if [[ $EUID -ne 0 ]]; then
    echo "需要 root 权限，正在提升..."
    exec sudo "$0" "$@"
fi

echo "开始配置 SSH..."

SSHD_CONFIG=""
for config in /etc/ssh/sshd_config /etc/sshd_config; do
    if [[ -f "$config" ]]; then
        SSHD_CONFIG="$config"
        break
    fi
done

if [[ -z "$SSHD_CONFIG" ]]; then
    echo "错误: 未找到 sshd_config"
    exit 1
fi

# 备份
backup="$SSHD_CONFIG.backup.$(date +%s)"
cp "$SSHD_CONFIG" "$backup"
echo "已备份到: $backup"

configure_ssh() {
    if grep -q "^PermitRootLogin" "$SSHD_CONFIG"; then
        sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' "$SSHD_CONFIG"
    else
        echo "PermitRootLogin yes" >> "$SSHD_CONFIG"
    fi

    if grep -q "^Port" "$SSHD_CONFIG"; then
        sed -i "s/^Port.*/Port $SSH_PORT/" "$SSHD_CONFIG"
    else
        echo "Port $SSH_PORT" >> "$SSHD_CONFIG"
    fi

    if ! grep -q "^PubkeyAuthentication yes" "$SSHD_CONFIG"; then
        echo "PubkeyAuthentication yes" >> "$SSHD_CONFIG"
    fi

    if [[ $DISABLE_PASS -eq 1 ]]; then
        if grep -q "^PasswordAuthentication" "$SSHD_CONFIG"; then
            sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
        else
            echo "PasswordAuthentication no" >> "$SSHD_CONFIG"
        fi
        echo "已禁用密码登录"
    fi
}

setup_ssh_key() {
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh

    if ! grep -Fxq "$SSH_PUB_KEY" /root/.ssh/authorized_keys 2>/dev/null; then
        echo "$SSH_PUB_KEY" >> /root/.ssh/authorized_keys
    fi

    chmod 600 /root/.ssh/authorized_keys
    chown -R root:root /root/.ssh
}

restart_ssh() {
    # systemd (Rocky, Ubuntu, Debian, CentOS 等)
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
            echo "SSH 服务已重启 (systemd)"
            return 0
        fi
    fi
    
    # OpenRC (Alpine Linux)
    if command -v rc-service >/dev/null 2>&1; then
        if rc-service sshd restart 2>/dev/null || rc-service ssh restart 2>/dev/null; then
            echo "SSH 服务已重启 (OpenRC)"
            return 0
        fi
    fi
    
    echo "警告: 无法自动重启 SSH 服务，请手动重启。"
    return 1
}

configure_ssh
setup_ssh_key

if sshd -t 2>/dev/null; then
    echo "SSH 配置验证通过"
    restart_ssh
else
    echo "错误: SSH 配置有误，正在恢复备份..."
    cp "$backup" "$SSHD_CONFIG"
    exit 1
fi

echo -e "\n配置完成:"
echo "root 登录: 已启用"
echo "SSH 端口: $SSH_PORT"
echo "公钥已写入: /root/.ssh/authorized_keys"
[[ $DISABLE_PASS -eq 1 ]] && echo "密码登录: 已禁用"
