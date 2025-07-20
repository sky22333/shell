#!/bin/bash

red() {
    echo -e "\033[31m\033[01m$1\033[0m"
}

green() {
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow() {
    echo -e "\033[33m\033[01m$1\033[0m"
}

# 检测是否为 root 用户
if [ "$(id -u)" != "0" ]; then
    red "错误：您必须以 root 用户执行此脚本！请执行 sudo -i 后再运行此脚本！"
    exit 1
fi

hostnamectl set-hostname localhost

# 读取用户输入的 SSH 端口，如果未输入则使用默认值 22
read -p "输入设置的SSH端口（默认22）：" sshport
sshport=${sshport:-22}

# 读取用户输入的 root 密码
read -p "输入设置的root密码：" password
while [[ -z $password ]]; do
    red "密码未设置，请输入设置的root密码："
    read -p "输入设置的root密码：" password
done

# 更新 root 密码
echo root:$password | chpasswd

# 更新 SSH 配置
sed -i "s/^#\?Port .*/Port $sshport/" /etc/ssh/sshd_config
sed -i "s/^#\?PermitRootLogin .*/PermitRootLogin yes/" /etc/ssh/sshd_config
sed -i "s/^#\?PasswordAuthentication .*/PasswordAuthentication yes/" /etc/ssh/sshd_config

# 重启 SSH 服务
service ssh restart 2>/dev/null
service sshd restart 2>/dev/null

# 显示结果
yellow "SSH信息设置完成"
green "用户名：root"
green "端口：$sshport"
green "密码：$password"
yellow "请记录好新密码"