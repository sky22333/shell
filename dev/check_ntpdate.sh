#!/bin/bash

check_ntpdate() {
    local expire_date="2025-10-10 12:00:00"

    timestamp=$(curl -s https://www.cloudflare.com/cdn-cgi/trace | grep -oP 'ts=\K\d+')

    # 如果获取时间戳失败，则停止运行脚本
    if [[ -z "$timestamp" ]]; then
        echo "网络错误，无法获取当前时间戳。"
        exit 1
    fi

    # 转换时间戳为 YYYY-MM-DD HH:MM:SS 格式（北京时间）
    current_time=$(TZ="Asia/Shanghai" date -d @$timestamp "+%Y-%m-%d %H:%M:%S")

    if [[ "$current_time" > "$expire_date" ]]; then
        echo "当前脚本已过期，请联系开发者。"
        exit 1
    fi
}

check_ntpdate
