#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 错误检查函数
check_error() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: $1${NC}"
        exit 1
    fi
}

echo -e "${YELLOW}请确保您已准备好TG机器人相关信息。准备好后，请按回车键开始部署。${NC}"
read

# 函数：获取用户输入
get_input() {
    local prompt="$1"
    local var_name="$2"
    read -p "$(echo -e ${YELLOW}$prompt: ${NC})" $var_name
}

# 获取用户输入
get_input "请输入TG机器人Token" TG_BOT_TOKEN
get_input "请输入TG账号ID" TG_BOT_ADMIN_ID
get_input "请输入认证Token" AUTH_TOKEN
get_input "请输入USDT域名" DOMAIN

# 下载和解压
echo -e "${GREEN}正在安装必要的软件...${NC}"
sudo apt install wget zip -yq
check_error "安装wget和zip失败"

echo -e "${GREEN}正在下载和解压文件...${NC}"
cd /usr/local
wget -O bepusdt.zip https://github.com/sky22333/bepusdt/releases/download/main/bepusdt-linux-amd64.zip
check_error "下载文件失败"
unzip bepusdt.zip
check_error "解压文件失败"
rm bepusdt.zip

# 配置软件自启
echo -e "${GREEN}正在配置软件开机自启...${NC}"
sudo chmod 755 /usr/local/bepusdt/bepusdt.service
check_error "赋予执行权限失败"
sudo mv /usr/local/bepusdt/bepusdt.service /etc/systemd/system/
check_error "移动服务文件失败"
sudo systemctl enable bepusdt.service
check_error "启用服务失败"

# 创建配置文件
echo -e "${GREEN}正在创建配置文件...${NC}"
cat > /usr/local/bepusdt/Environment.conf << EOL
EXPIRE_TIME=600
USDT_RATE=
AUTH_TOKEN=$AUTH_TOKEN
LISTEN=:7000
TRADE_IS_CONFIRMED=0
APP_URI=https://$DOMAIN
WALLET_ADDRESS=
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_BOT_ADMIN_ID=$TG_BOT_ADMIN_ID
EOL
check_error "创建配置文件失败"

# 启动软件
echo -e "${GREEN}正在启动软件...${NC}"
systemctl start bepusdt.service
check_error "启动服务失败"

# 查看软件状态
echo -e "${GREEN}查看软件状态...${NC}"
status_output=$(systemctl is-active bepusdt.service 2>&1)
if [ "$status_output" = "active" ]; then
    echo -e "${GREEN}bepusdt 服务已成功启动并正在运行！服务监听在7000端口。${NC}"
else
    echo -e "${RED}警告: bepusdt 服务可能未正常运行。状态: $status_output${NC}"
    echo -e "${YELLOW}您可以稍后使用 'systemctl status bepusdt.service' 命令检查。${NC}"
fi


# 询问是否需要自动开启域名反代
read -p "$(echo -e ${YELLOW}是否需要自动开启域名反代？（这将占用80和443端口，请确保当前环境没有运行网站服务，回车不开启）[y/N]: ${NC})" answer

if [ ! -d /etc/apt/sources.list.d/ ]; then
    mkdir -p /etc/apt/sources.list.d/
    check_error "创建sources.list.d目录失败"
fi

if [[ $answer =~ ^[Yy]$ ]]; then
    # 安装Caddy
    echo -e "${GREEN}正在安装Caddy...${NC}"
    sudo apt install -yq debian-keyring debian-archive-keyring apt-transport-https curl
    check_error "安装依赖失败"
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    check_error "下载Caddy GPG密钥失败"
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    check_error "添加Caddy源失败"
    sudo apt update
    check_error "更新软件包列表失败"
    sudo apt install caddy -yq
    check_error "安装Caddy失败"

    # 写入Caddy配置
    echo -e "${GREEN}正在配置Caddy...${NC}"
    sudo tee /etc/caddy/Caddyfile > /dev/null << EOL
$DOMAIN {
    encode gzip
    reverse_proxy localhost:7000
}
EOL
    check_error "写入Caddy配置失败"

    # 重启Caddy
    echo -e "${GREEN}正在重启Caddy...${NC}"
    sudo systemctl restart caddy
    check_error "重启Caddy失败"
    echo -e "${GREEN}域名反代已配置完成。${NC}"
else
    echo -e "${YELLOW}你选择跳过反代，请自行将你输入的域名反代到7000端口。${NC}"
fi

# 添加结束总结
echo -e "\n${YELLOW}=============== 部署成功 ===============${NC}"
echo -e "${GREEN}对接域名: $DOMAIN ${NC}"
echo -e "${GREEN}认证Token: $AUTH_TOKEN ${NC}"
echo -e "${GREEN}服务端口: 7000${NC}"
if [[ $answer =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}反向代理: 已配置（使用Caddy）${NC}"
else
    echo -e "${YELLOW}反向代理: 未配置（请自行将域名反代到7000端口）${NC}"
fi
echo -e "${YELLOW}==========================================${NC}"
echo -e "\n${GREEN}请记录好上述信息，特别是认证Token，它用于支付对接。${NC}"
