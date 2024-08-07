#!/bin/bash

sudo ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

sudo hostnamectl set-hostname localhost

# 清空 /etc/motd 文件并设置内容
cat << 'EOF' > /etc/motd
EOF

# 清空 ~/.bashrc 文件并设置内容
echo "" > ~/.bashrc

# 设置完整的纯文本终端欢迎语
cat << 'EOF' >> ~/.bashrc
# 自定义终端欢迎语
if [ -n "$PS1" ]; then
    echo -e "欢迎上机！"
fi
EOF

# 安装 Docker
if ! command -v docker &> /dev/null; then
    echo "安装 Docker..."
    curl -fsSL https://get.docker.com | sh
else
    echo "Docker 已经安装，跳过安装步骤。"
fi

# 安装 Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo "安装 Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
else
    echo "Docker Compose 已经安装，跳过安装步骤。"
fi

echo "配置完成！"
