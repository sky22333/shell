#!/bin/bash
# Go 自动安装配置脚本 (支持 Debian/Ubuntu 和 RHEL/CentOS/Fedora)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检测系统类型
if grep -qiE 'debian|ubuntu' /etc/os-release; then
    OS_TYPE="debian"
    PKG_MANAGER="apt-get"
elif grep -qiE 'rhel|centos|fedora|rocky|alma' /etc/os-release; then
    OS_TYPE="rhel"
    if command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    else
        PKG_MANAGER="yum"
    fi
else
    echo -e "${RED}错误：不支持的系统${NC}"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}请使用 root 权限运行${NC}"
    exit 1
fi

# 安装必要工具
if ! command -v wget &>/dev/null; then
    ${PKG_MANAGER} install -y wget > /dev/null 2>&1
fi

DEFAULT_VERSION="1.26.3"

read -p "Go 版本 [默认: ${DEFAULT_VERSION}]: " GO_VERSION
GO_VERSION=${GO_VERSION:-$DEFAULT_VERSION}

if ! [[ "$GO_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}版本号格式错误${NC}"
    exit 1
fi

# 架构检测
ARCH=$(uname -m)
case "${ARCH}" in
    x86_64) GO_ARCH="amd64" ;;
    aarch64|arm64) GO_ARCH="arm64" ;;
    *) echo -e "${RED}不支持的架构: ${ARCH}${NC}"; exit 1 ;;
esac

GO_TAR="go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
GO_URL="https://dl.google.com/go/${GO_TAR}"

# 卸载旧版本
if command -v go &>/dev/null; then
    echo -e "${YELLOW}已安装: $(go version)${NC}"
    read -p "卸载并重装? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf /usr/local/go
        sed -i '/# GoLang/d' /etc/profile
        sed -i '/export GOROOT\|export GOPATH\|export PATH=\$GOROOT/d' /etc/profile
    else
        exit 0
    fi
fi

# 下载安装
cd /tmp
rm -f "${GO_TAR}"
echo -e "${GREEN}下载 Go ${GO_VERSION}...${NC}"
wget -q --show-progress "${GO_URL}" || {
    echo -e "${RED}下载失败${NC}"
    exit 1
}

echo -e "${GREEN}安装中...${NC}"
rm -rf /usr/local/go
tar -C /usr/local -xzf "${GO_TAR}"

# 配置环境变量
cat >> /etc/profile <<'EOF'

# GoLang
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
EOF

for USER_HOME in /home/* /root; do
    if [ -d "${USER_HOME}" ]; then
        USER=$(basename "${USER_HOME}")
        PROFILE="${USER_HOME}/.profile"
        [ "${OS_TYPE}" = "rhel" ] && PROFILE="${USER_HOME}/.bash_profile"
        
        sed -i '/# GoLang/d' "${PROFILE}" 2>/dev/null
        sed -i '/export GOROOT\|export GOPATH\|export PATH=\$GOROOT/d' "${PROFILE}" 2>/dev/null
        
        cat >> "${PROFILE}" <<'EOF'

# GoLang
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
EOF
        
        mkdir -p "${USER_HOME}/go"/{bin,pkg,src}
        chown -R "${USER}:${USER}" "${USER_HOME}/go" 2>/dev/null || true
    fi
done

rm -f "/tmp/${GO_TAR}"

export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH

echo -e "${GREEN}完成! $(go version)${NC}"
echo -e "GOPATH: ~/go | 立即生效: source ~/.profile"
