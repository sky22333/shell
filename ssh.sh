#!/bin/bash

# 检查并安装 sshpass
if ! command -v sshpass &> /dev/null; then
    echo "sshpass could not be found, attempting to install..."
    apt-get update && apt-get install -y sshpass
fi

# 服务器信息文件路径
server_info_file="ssh.txt"

# 检查服务器信息文件是否存在
if [ ! -f "$server_info_file" ]; then
    echo "Server information file not found: $server_info_file"
    exit 1
fi

# 循环，直到用户决定停止
while true; do
    # 获取用户输入的命令
    echo "Please enter the script/command you want to execute on all servers:"
    read -r command

    # 如果用户没有输入命令，则询问是否退出
    if [ -z "$command" ]; then
        echo "No command entered. Do you want to exit? (y/n)"
        read -r answer
        if [ "$answer" = "y" ]; then
            break
        else
            continue
        fi
    fi

    # 读取服务器信息并执行命令
    while IFS=' ' read -r ip port user password; do
        echo "Connecting to $ip..."
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "$user@$ip" "$command"
    done < "$server_info_file"

    # 询问用户是否继续输入另一个命令
    echo "Do you want to execute another script/command? (y/n)"
    read -r answer
    if [ "$answer" != "y" ]; then
        break
    fi
done

echo "Script execution completed."
