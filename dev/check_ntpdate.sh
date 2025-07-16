#!/bin/bash

# 封装脚本过期函数
check_ntpdate() {
    # 设置过期时间
    local expire_date="2025-04-10 12:00:00"

    # date -d "$(curl -sI https://www.bing.com | grep -i '^date:' | cut -d' ' -f2-)" +'%Y-%m-%d %H:%M:%S UTC+8'
    # 获取时间戳（从 https://www.cloudflare.com/cdn-cgi/trace 获取）
    timestamp=$(curl -s https://www.cloudflare.com/cdn-cgi/trace | grep -oP 'ts=\K\d+')

    # 如果获取时间戳失败，则停止运行脚本
    if [[ -z "$timestamp" ]]; then
        echo "网络错误，无法获取当前时间戳。"
        exit 1
    fi

    # 转换时间戳为 YYYY-MM-DD HH:MM:SS 格式（北京时间）
    current_time=$(TZ="Asia/Shanghai" date -d @$timestamp "+%Y-%m-%d %H:%M:%S")

    # 判断当前时间是否超过过期日期
    if [[ "$current_time" > "$expire_date" ]]; then
        echo "当前脚本已过期，请联系开发者。"
        exit 1
    fi
}

# 调用函数执行检查
check_ntpdate
