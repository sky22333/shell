#!/bin/bash

# SSH公钥批量配置脚本
# 用法: ./ssh-pub.sh -pub "your-public-key"

set -euo pipefail

# 默认配置
DEFAULT_PORT=22
SSH_PUB_KEY=""
SSH_PORT="$DEFAULT_PORT"

# 参数解析
usage() {
    echo "用法: $0 -pub \"公钥内容\" [-port 端口号]"
    echo "示例: $0 -pub \"ssh-ed25519 AAAAC3Nza..................\" -port 2222"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -pub)
            SSH_PUB_KEY="$2"
            shift 2
            ;;
        -port)
            SSH_PORT="$2"
            shift 2
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

# 检查必需参数
if [[ -z "$SSH_PUB_KEY" ]]; then
    echo "错误: 必须指定公钥 (-pub)"
    usage
fi

# 权限检查
if [[ $EUID -ne 0 ]]; then
    echo "需要root权限，正在提升..."
    exec sudo "$0" "$@"
fi

echo "开始配置SSH..."

# SSH配置文件路径检测
SSHD_CONFIG=""
for config in /etc/ssh/sshd_config /etc/sshd_config; do
    if [[ -f "$config" ]]; then
        SSHD_CONFIG="$config"
        break
    fi
done

if [[ -z "$SSHD_CONFIG" ]]; then
    echo "错误: 未找到SSH配置文件"
    exit 1
fi

# 备份原配置
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.backup.$(date +%s)"

# 配置SSH
configure_ssh() {
    # 允许root登录
    if grep -q "^PermitRootLogin" "$SSHD_CONFIG"; then
        sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' "$SSHD_CONFIG"
    else
        echo "PermitRootLogin yes" >> "$SSHD_CONFIG"
    fi
    
    # 设置端口
    if grep -q "^Port" "$SSHD_CONFIG"; then
        sed -i "s/^Port.*/Port $SSH_PORT/" "$SSHD_CONFIG"
    else
        echo "Port $SSH_PORT" >> "$SSHD_CONFIG"
    fi
    
    # 确保密钥认证开启
    if ! grep -q "^PubkeyAuthentication yes" "$SSHD_CONFIG"; then
        echo "PubkeyAuthentication yes" >> "$SSHD_CONFIG"
    fi
}

# 设置SSH密钥
setup_ssh_key() {
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    
    # 写入公钥，避免重复
    if ! grep -Fxq "$SSH_PUB_KEY" /root/.ssh/authorized_keys 2>/dev/null; then
        echo "$SSH_PUB_KEY" >> /root/.ssh/authorized_keys
    fi
    
    chmod 600 /root/.ssh/authorized_keys
    chown -R root:root /root/.ssh
}

# 重启SSH服务 - 兼容多种系统
restart_ssh() {
    local ssh_service=""
    
    # 检测SSH服务名称
    for service in sshd ssh; do
        if systemctl list-unit-files --type=service 2>/dev/null | grep -q "^${service}.service"; then
            ssh_service="$service"
            break
        fi
    done
    
    if [[ -n "$ssh_service" ]]; then
        if systemctl restart "$ssh_service" 2>/dev/null; then
            echo "SSH服务已重启 (systemctl)"
            return 0
        fi
    fi
    
    # 回退到传统方式
    for cmd in "service ssh restart" "service sshd restart" "/etc/init.d/ssh restart" "/etc/init.d/sshd restart"; do
        if $cmd 2>/dev/null; then
            echo "SSH服务已重启 (传统方式)"
            return 0
        fi
    done
    
    echo "警告: 无法自动重启SSH服务，请手动重启"
    return 1
}

# 执行配置
configure_ssh
setup_ssh_key

# 验证配置
if sshd -t 2>/dev/null; then
    echo "SSH配置验证通过"
    restart_ssh
else
    echo "错误: SSH配置有误，正在恢复备份..."
    cp "${SSHD_CONFIG}.backup."* "$SSHD_CONFIG" 2>/dev/null || true
    exit 1
fi

# 显示结果
echo -e "\n配置完成:"
echo "Root登录: 已启用"
echo "SSH端口: $SSH_PORT"
echo "公钥已添加到: /root/.ssh/authorized_keys"
