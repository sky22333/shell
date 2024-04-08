#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

apt update
apt install -y iproute2

read -p "请输入要限制带宽的端口号（多个端口用逗号分隔）: " PORTS
read -p "请输入限速值（单位为M）: " LIMIT

if [ -z "$PORTS" ] || [ -z "$LIMIT" ]; then
    echo "错误：端口号不能为空。"
    exit 1
fi

if ! [[ "$LIMIT" =~ ^[0-9]+$ ]]; then
    echo "错误：限速值必须是一个数字。"
    exit 1
fi

INTERFACE="eth0"  # 要限制的网络接口

IFS=',' read -ra PORT_ARRAY <<< "$PORTS"

for PORT in "${PORT_ARRAY[@]}"
do
    tc qdisc add dev "$INTERFACE" root handle 1: htb default 12
    tc class add dev "$INTERFACE" parent 1: classid 1:1 htb rate "${LIMIT}"mbit
    tc class add dev "$INTERFACE" parent 1:1 classid 1:12 htb rate "${LIMIT}"mbit
    tc filter add dev "$INTERFACE" protocol ip parent 1:0 prio 1 u32 match ip dport "$PORT" 0xffff flowid 1:12
    echo -e "${GREEN}网络接口 eth0 的端口 $PORT 带宽限制已设置为 ${LIMIT}Mbit。${NC}"
done

echo -e "${YELLOW}如果要更改配置请先清除限速规则：sudo tc qdisc del dev $INTERFACE root${NC}"
