#!/bin/bash

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查是否以root权限运行
if [ "$(id -u)" != "0" ]; then
   echo -e "${RED}此脚本需要root权限运行，请输入 sudo -i 后再执行此脚本${NC}" 1>&2
   exit 1
fi

# 检查是否安装了iproute2
if ! command -v tc &> /dev/null
then
    echo -e "${BLUE}iproute2未安装，正在安装...${NC}"
    if ! apt update -q && apt install -yq iproute2; then
        echo -e "${RED}安装iproute2失败。请检查您的网络连接和系统状态。${NC}"
        exit 1
    fi
else
    echo -e "${BLUE}iproute2已安装。${NC}"
fi

# 获取默认网络接口
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

if [ -z "$INTERFACE" ]; then
    echo -e "${RED}错误：无法检测到默认网络接口。${NC}"
    exit 1
fi

echo -e "${BLUE}检测到默认网络接口: $INTERFACE${NC}"

# 检查是否存在限速规则
if tc qdisc show dev $INTERFACE | grep -q "htb"; then
    echo -e "${YELLOW}当前存在限速规则：${NC}"
    tc -s qdisc ls dev $INTERFACE
    echo -e "${GREEN}如果要更改配置请先清除限速规则，请运行以下命令，然后重新执行脚本。${NC}"
    echo -e "${YELLOW}sudo tc qdisc del dev $INTERFACE root${NC}"
    exit 0
fi

printf "${GREEN}请输入要限制带宽的端口号（多个端口用逗号分隔）: ${NC}"
read PORTS
printf "${GREEN}请输入限速值（单位为M）: ${NC}"
read LIMIT

if [ -z "$PORTS" ] || [ -z "$LIMIT" ]; then
    echo -e "${RED}错误：端口号和限速值不能为空。${NC}"
    exit 1
fi

if ! [[ "$LIMIT" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}错误：限速值必须是一个数字。${NC}"
    exit 1
fi

IFS=',' read -ra PORT_ARRAY <<< "$PORTS"

# 创建根qdisc
tc qdisc add dev "$INTERFACE" root handle 1: htb default 12
tc class add dev "$INTERFACE" parent 1: classid 1:1 htb rate "${LIMIT}"mbit
tc class add dev "$INTERFACE" parent 1:1 classid 1:12 htb rate "${LIMIT}"mbit

for PORT in "${PORT_ARRAY[@]}"
do
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
        echo -e "${RED}错误：无效的端口号 $PORT。端口号必须在1-65535之间。${NC}"
        continue
    fi
    tc filter add dev "$INTERFACE" protocol ip parent 1:0 prio 1 u32 match ip dport "$PORT" 0xffff flowid 1:12
    echo -e "${GREEN}网络接口 $INTERFACE 的端口 $PORT 带宽限制已设置为 ${LIMIT}Mbit。${NC}"
done

echo -e "${YELLOW}如果要更改配置请先清除限速规则，请运行以下命令，然后重新执行脚本。${NC}"
echo -e "${YELLOW}sudo tc qdisc del dev $INTERFACE root${NC}"
