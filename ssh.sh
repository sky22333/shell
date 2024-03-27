#!/bin/bash

# 定义颜色
green='\033[0;32m'
none='\033[0m'

# 检查并安装 sshpass
if ! command -v sshpass &> /dev/null; then
    echo "sshpass 没有找到，正在尝试安装..."
    apt-get update && apt-get install -y sshpass
fi

# 服务器信息文件路径
server_info_file="servers.txt"

# 检查服务器信息文件是否存在
if [ ! -f "$server_info_file" ]; then
    echo "服务器信息文件未找到: $server_info_file"
    exit 1
fi

# 循环，直到用户决定停止
while true; do
    echo "请输入要在所有服务器上执行的脚本/命令:"
    read -r command

    # 如果用户没有输入命令，则询问是否退出
    if [ -z "$command" ]; then
        echo "未输入任何命令。你想要退出吗？(y/n)"
        read -r answer
        if [ "$answer" = "y" ]; then
            break
        else
            continue
        fi
    fi

    # 读取服务器信息并执行命令
    while IFS=' ' read -r ip port user password; do
        echo -e "正在连接到 ${green}$ip${none}..."
        output=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "$user@$ip" -n "$command" 2>&1)
        exit_status=$?
        if [ $exit_status -eq 0 ]; then
            echo -e "${green}$ip 上的命令执行成功:${none}"
            echo -e "${green}$output${none}"
        else
            echo -e "${green}$ip 上的命令执行失败，错误信息:${none}"
            echo -e "${green}$output${none}"
        fi
    done < "$server_info_file"

    # 询问用户是否继续输入另一个命令
    echo "你想要执行另一个脚本/命令吗？(y/n)"
    read -r answer
    if [ "$answer" != "y" ]; then
        break
    fi
done

echo "脚本执行完毕。"
