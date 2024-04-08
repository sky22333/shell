#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

apt update
apt install -y iproute2

read -p "请输入要限制带宽的端口号（多个端口用逗号分隔）: " PORTS

read -p "请输入限速值（单位为M）: " LIMIT

INTERFACE="eth0"  # 要限制的网络接口

IFS=',' read -ra PORT_ARRAY <<< "$PORTS"

for PORT in "${PORT_ARRAY[@]}"
do
    tc qdisc add dev $INTERFACE root handle 1: htb default 12
    tc class add dev $INTERFACE parent 1: classid 1:1 htb rate ${LIMIT}mbit
    tc class add dev $INTERFACE parent 1:1 classid 1:12 htb rate ${LIMIT}mbit
    tc filter add dev $INTERFACE protocol ip parent 1:0 prio 1 u32 match ip dport $PORT 0xffff flowid 1:12
    echo -e "${GREEN}端口 $PORT 的带宽限制已设置为 ${LIMIT}Mbit。${NC}"
done

echo -e "${YELLOW}要解除限速请执行：sudo tc qdisc del dev eth0 root${NC}"
systemctl restart systemd-networkd
