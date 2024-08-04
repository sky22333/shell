#!/bin/bash

sudo ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

sudo bash -c 'echo "127.0.0.1 wovow" >> /etc/hosts'

sudo hostnamectl set-hostname wovow

# 清空 /etc/motd 文件并设置内容
cat << 'EOF' > /etc/motd
《C语言从研发到脱发》
《C++从入门到放弃》
《Java从跨平台到跨行业》
《iOS开发从入门到下架》
《Android开发大全——从开始到转行》
《PHP由初学至搬砖》
《黑客攻防:从入门到入狱》
《MySQL从删库到跑路》
《服务器运维管理从网络异常到硬盘全红》
《服务器运维管理从网维到网管》
《Debug455个经典案例，让电脑开机蓝屏》
《零基础学C语言，学完负基础》
《CSS从绘制框架到改行画画》
EOF

# 清空 ~/.bashrc 文件并设置内容
echo "" > ~/.bashrc

# 设置完整的纯文本终端欢迎语
cat << 'EOF' >> ~/.bashrc
# 自定义终端欢迎语
if [ -n "$PS1" ]; then
    echo -e "\e[32m欢迎大佬上机！\e[0m"
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

echo "配置完成！欢迎大佬上机！"
