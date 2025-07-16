#!/bin/bash
# Go 自动安装配置脚本 (适用于Debian/Ubuntu)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if ! grep -qiE 'debian|ubuntu' /etc/os-release; then
    echo -e "${RED}错误：本脚本仅适用于Debian/Ubuntu系统${NC}"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}请使用 sudo 或以 root 用户运行此脚本${NC}"
    exit 1
fi

DEFAULT_VERSION="1.24.0"

read -p "请输入要安装的 Go 版本 [默认: ${DEFAULT_VERSION}]: " GO_VERSION
GO_VERSION=${GO_VERSION:-$DEFAULT_VERSION}

if ! [[ "$GO_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}错误：版本号格式不正确，版本号可在 https://golang.org/dl 查看${NC}"
    exit 1
fi

GO_TAR="go${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://dl.google.com/go/${GO_TAR}"

if command -v go &>/dev/null; then
    echo -e "${YELLOW}检测到已安装Go，当前版本: $(go version)${NC}"
    read -p "是否要卸载当前版本? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}卸载旧版Go...${NC}"
        rm -rf /usr/local/go
        sed -i '/# GoLang/d' /etc/profile
        sed -i '/export GOROOT/d' /etc/profile
        sed -i '/export GOPATH/d' /etc/profile
        sed -i '/export PATH=\$GOROOT/d' /etc/profile
    else
        echo -e "${YELLOW}保留现有安装，退出脚本${NC}"
        exit 0
    fi
fi

echo -e "${YELLOW}检查是否存在旧的安装包...${NC}"
cd /tmp
if [ -f "${GO_TAR}" ]; then
    echo -e "${YELLOW}删除旧的安装包：${GO_TAR}${NC}"
    rm -f "${GO_TAR}"
fi

echo -e "${GREEN}开始下载 Go ${GO_VERSION} 安装包...${NC}"
wget --progress=bar:force "${GO_URL}"
if [ $? -ne 0 ]; then
    echo -e "${RED}下载失败，请检查网络连接和版本号是否正确${NC}"
    echo "可用的Go版本可在 https://golang.org/dl/ 查看"
    exit 1
fi

echo -e "${GREEN}安装 Go 到 /usr/local...${NC}"
rm -rf /usr/local/go
tar -C /usr/local -xzf "${GO_TAR}"

echo -e "${GREEN}配置环境变量...${NC}"
cat >> /etc/profile <<EOF

# GoLang Environment
export GOROOT=/usr/local/go
export GOPATH=\$HOME/go
export PATH=\$GOROOT/bin:\$GOPATH/bin:\$PATH
EOF

for USER_HOME in /home/* /root; do
    USER=$(basename "${USER_HOME}")
    if [ -d "${USER_HOME}" ]; then
        cat >> "${USER_HOME}/.profile" <<EOF

# GoLang Environment
export GOROOT=/usr/local/go
export GOPATH=\$HOME/go
export PATH=\$GOROOT/bin:\$GOPATH/bin:\$PATH
EOF
        chown "${USER}:${USER}" "${USER_HOME}/.profile"
    fi
done

echo -e "${GREEN}创建 GOPATH 目录...${NC}"
for USER_HOME in /home/* /root; do
    if [ -d "${USER_HOME}" ]; then
        mkdir -p "${USER_HOME}/go"{,/bin,/pkg,/src}
        chown -R "$(basename "${USER_HOME}"):$(basename "${USER_HOME}")" "${USER_HOME}/go"
    fi
done

source /etc/profile

echo -e "${GREEN}验证安装...${NC}"
if ! command -v go &>/dev/null; then
    echo -e "${RED}Go 安装失败，请检查错误信息${NC}"
    exit 1
fi

echo -e "${GREEN}Go 安装成功！版本信息:${NC}"
go version

echo -e "
${GREEN}安装完成！Go ${GO_VERSION} 已成功安装并配置。${NC}

${YELLOW}提示:
1. 新终端会话会自动加载 Go 环境变量
2. 当前会话可执行 ${NC}${GREEN}source ~/.profile${NC}${YELLOW} 立即生效
3. Go 工作目录 (GOPATH) 已创建在 ${NC}${GREEN}~/go${NC}

如需卸载，请删除 ${YELLOW}/usr/local/go${NC} 目录。
"
