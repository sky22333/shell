#!/bin/sh

red() {
    printf "\033[31m\033[01m%s\033[0m\n" "$1"
}

green() {
    printf "\033[32m\033[01m%s\033[0m\n" "$1"
}

yellow() {
    printf "\033[33m\033[01m%s\033[0m\n" "$1"
}

if [ "$(id -u)" != "0" ]; then
    red "错误：您必须以 root 用户执行此脚本！请执行 sudo -i 后再运行此脚本！"
    exit 1
fi

hostnamectl set-hostname localhost 2>/dev/null || hostname localhost 2>/dev/null || true
echo "" > /etc/motd 2>/dev/null || true

printf "输入设置的SSH端口（默认22）："
read sshport
if [ -z "$sshport" ]; then
    sshport="22"
fi

printf "输入设置的root密码："
read password
while [ -z "$password" ]; do
    red "密码未设置，请输入设置的root密码："
    printf "输入设置的root密码："
    read password
done

if command -v chpasswd >/dev/null 2>&1; then
    echo "root:$password" | chpasswd
elif [ -x /usr/sbin/chpasswd ]; then
    echo "root:$password" | /usr/sbin/chpasswd
elif [ -x /usr/bin/chpasswd ]; then
    echo "root:$password" | /usr/bin/chpasswd
elif command -v passwd >/dev/null 2>&1; then
    printf "%s\n%s\n" "$password" "$password" | passwd root 2>/dev/null
else
    red "错误：未找到 passwd 或 chpasswd 命令，无法设置密码！"
    exit 1
fi

sed -i "s/^#\?Port .*/Port $sshport/" /etc/ssh/sshd_config 2>/dev/null
sed -i "s/^#\?PermitRootLogin .*/PermitRootLogin yes/" /etc/ssh/sshd_config 2>/dev/null
sed -i "s/^#\?PasswordAuthentication .*/PasswordAuthentication yes/" /etc/ssh/sshd_config 2>/dev/null

if command -v rc-service >/dev/null 2>&1; then
    rc-service sshd restart 2>/dev/null || rc-service ssh restart 2>/dev/null
elif command -v systemctl >/dev/null 2>&1; then
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
else
    service ssh restart 2>/dev/null || service sshd restart 2>/dev/null
fi

yellow "SSH信息设置完成"
green "用户名：root"
green "端口：$sshport"
green "密码：$password"
yellow "请记录好新密码"
