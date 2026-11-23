#!/bin/bash
# ==========================================
# Debian/Ubuntu 内核更新脚本
# 支持多架构 (amd64/arm64)、防失联、保留云端网络配置
# 适用系统：Debian 11+ / Ubuntu 18.04+
# ==========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

check_env() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：必须使用 root 权限运行此脚本。${NC}"
        exit 1
    fi

    ARCH=$(dpkg --print-architecture)
    OS=$(awk -F= '/^ID=/{print $2}' /etc/os-release | tr -d '"')
    
    echo -e "${BLUE}系统检测结果：${NC} OS=${OS}, 架构=${ARCH}"

    if [[ "$OS" == "ubuntu" ]]; then
        TARGET_IMAGE="linux-image-generic"
        TARGET_HEADERS="linux-headers-generic"
    elif [[ "$OS" == "debian" ]]; then
        TARGET_IMAGE="linux-image-${ARCH}"
        TARGET_HEADERS="linux-headers-${ARCH}"
    else
        echo -e "${RED}错误：不支持的操作系统 ($OS)，仅支持 Debian / Ubuntu。${NC}"
        exit 1
    fi
}

confirm_operation() {
    echo -e "\n${YELLOW}⚠️  安全提示：即将切换到标准内核 ⚠️${NC}"
    echo -e "当前内核: $(uname -r)"
    echo -e "目标安装: ${TARGET_IMAGE} / ${TARGET_HEADERS}"
    echo -e "操作逻辑: ${GREEN}安装新内核 -> 更新启动项 -> 卸载专有云内核${NC}"
    
    echo ""
    read -p "$(echo -e ${YELLOW}"确认继续执行？[y/N]: "${NC})" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}操作已取消。${NC}"
        exit 0
    fi
    echo -e "${GREEN}开始执行...${NC}\n"
}

change_mirrors() {
    echo -e "${YELLOW}[1/4] 检查并配置软件源...${NC}"
    if curl -sSL --max-time 3 https://www.cloudflare.com/cdn-cgi/trace | grep -q 'loc=CN'; then
        echo -e "检测为境内网络，使用阿里云源..."
        bash <(curl -sSL https://gitee.com/SuperManito/LinuxMirrors/raw/main/ChangeMirrors.sh) \
          --source mirrors.aliyun.com --protocol http --use-intranet-source false \
          --install-epel true --backup true --upgrade-software false \
          --clean-cache false --ignore-backup-tips --pure-mode > /dev/null 2>&1
    else
        echo -e "非境内网络，使用官方源..."
        bash <(curl -sSL https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/ChangeMirrors.sh) \
          --use-official-source true --protocol http --use-intranet-source false \
          --install-epel true --backup true --upgrade-software false \
          --clean-cache false --ignore-backup-tips --pure-mode > /dev/null 2>&1
    fi
    apt-get update -qq
}

install_standard_kernel() {
    echo -e "${YELLOW}[2/4] 正在安装标准内核 ($TARGET_IMAGE) ...${NC}"
    
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y --reinstall "$TARGET_IMAGE" "$TARGET_HEADERS"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误：标准内核安装失败！已中止后续危险操作。${NC}"
        exit 1
    fi

    local std_vmlinuz=$(ls /boot/vmlinuz-* 2>/dev/null | grep -vE 'cloud|aws|gcp|azure|kvm|oracle|ibm' | head -n 1)
    if [ -z "$std_vmlinuz" ]; then
        echo -e "${RED}错误：未能找到已安装的标准内核映像文件，拒绝继续！${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ 标准内核已成功写入系统 ($std_vmlinuz)${NC}"
}

configure_grub() {
    echo -e "${YELLOW}[3/4] 安全更新 GRUB 配置...${NC}"
    
    mkdir -p /root/grub_backup
    cp -a /etc/default/grub "/root/grub_backup/grub.bak.$(date +%s)" 2>/dev/null
    
    sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=0/' /etc/default/grub
    if ! grep -q "^GRUB_DEFAULT=" /etc/default/grub; then
        echo "GRUB_DEFAULT=0" >> /etc/default/grub
    fi
    
    sed -i 's/^#GRUB_DISABLE_OS_PROBER.*/GRUB_DISABLE_OS_PROBER=true/' /etc/default/grub
    if ! grep -q "^GRUB_DISABLE_OS_PROBER=" /etc/default/grub; then
        echo "GRUB_DISABLE_OS_PROBER=true" >> /etc/default/grub
    fi
    
    update-grub
    echo -e "${GREEN}✓ GRUB 更新完成，已确保第一顺位启动新内核。${NC}"
}

remove_cloud_kernels() {
    echo -e "${YELLOW}[4/4] 正在识别并卸载专有云内核...${NC}"
    
    # 正则匹配各类云内核包名：cloud, aws, gcp, azure, kvm, oracle
    local cloud_pkgs=$(dpkg -l | awk '/linux-(image|headers|modules)-.*(cloud|aws|gcp|azure|kvm|oracle|ibm)/ {print $2}')
    
    if [ -z "$cloud_pkgs" ]; then
        echo -e "${GREEN}未检测到需要清理的专有云内核包。${NC}"
        return 0
    fi
    
    echo -e "将卸载以下云内核包："
    echo "$cloud_pkgs" | sed 's/^/  - /'
    
    export DEBIAN_FRONTEND=noninteractive
    apt-get purge -y $cloud_pkgs
    apt-get autoremove -y --purge
    update-grub > /dev/null 2>&1
    echo -e "${GREEN}✓ 云内核清理完成。${NC}"
}

main() {
    clear
    echo -e "${GREEN}==========================================${NC}"
    echo -e "${GREEN}   Debian/Ubuntu 切换标准内核脚本            ${NC}"
    echo -e "${GREEN}==========================================${NC}"
    
    check_env
    confirm_operation
    change_mirrors
    install_standard_kernel
    configure_grub
    remove_cloud_kernels
    
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}🎉 所有操作已成功执行！${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}下一步：${NC}"
    echo -e "请重启服务器，重启后运行 ${BLUE}uname -r${NC} 确认内核是否已变更为标准版。\n"
    
    read -p "$(echo -e ${YELLOW}"立即重启系统？[y/N]: "${NC})" reboot_now
    if [[ "$reboot_now" =~ ^[Yy]$ ]]; then
        sync
        reboot
    fi
}

main "$@"
