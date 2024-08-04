#!/bin/bash

sudo hostnamectl set-hostname wovow

sudo bash -c 'echo "127.0.0.1 wovow" >> /etc/hosts'

echo "" > ~/.bashrc

cat << 'EOF' >> ~/.bashrc
# 自定义终端欢迎语
if [ -n "$PS1" ]; then
    echo -e "\e[32m《C语言从研发到脱发》\e[0m"
    echo -e "\e[32m《C++从入门到放弃》\e[0m"
    echo -e "\e[32m《Java从跨平台到跨行业》\e[0m"
    echo -e "\e[32m《iOS开发从入门到下架》\e[0m"
    echo -e "\e[32m《Android开发大全——从开始到转行》\e[0m"
    echo -e "\e[32m《PHP由初学至搬砖》\e[0m"
    echo -e "\e[32m《黑客攻防:从入门到入狱》\e[0m"
    echo -e "\e[32m《MySQL从删库到跑路》\e[0m"
    echo -e "\e[32m《服务器运维管理从网络异常到硬盘全红》\e[0m"
    echo -e "\e[32m《服务器运维管理从网维到网管》\e[0m"
    echo -e "\e[32m《Office三件套从入门到手写》\e[0m"
    echo -e "\e[32m《Debug455个经典案例，让电脑开机蓝屏》\e[0m"
    echo -e "\e[32m《零基础学C语言，学完负基础》\e[0m"
    echo -e "\e[32m《CSS从绘制框架到改行画画》\e[0m"
fi
EOF

if ! command -v docker &> /dev/null; then
    echo "安装 Docker..."
    curl -fsSL https://get.docker.com | sh
else
    echo "Docker 已经安装，跳过安装步骤。"
fi

if ! command -v docker-compose &> /dev/null; then
    echo "安装 Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
else
    echo "Docker Compose 已经安装，跳过安装步骤。"
fi

source ~/.bashrc

echo "设置完成！欢迎大佬上机！"
