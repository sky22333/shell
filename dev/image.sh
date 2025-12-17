#!/bin/bash
# Debian/Ubuntu 内核切换脚本
# 功能：从 Cloud 内核切换到标准内核
# 适用：Debian 11+/Ubuntu 18.04+

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查 root 权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：必须使用 root 权限运行此脚本${NC}"
        exit 1
    fi
}

# 检测地理位置
detect_region() {
    echo -e "${BLUE}检测网络位置...${NC}"

    local TRACE_URLS=(
        "https://www.cloudflare.com/cdn-cgi/trace"
        "https://www.visa.cn/cdn-cgi/trace"
    )

    local trace_info=""
    for url in "${TRACE_URLS[@]}"; do
        trace_info=$(curl -sSL --max-time 8 "$url" 2>/dev/null) && break
    done

    if echo "$trace_info" | grep -q '^loc=CN'; then
        echo -e "${GREEN}CN 网络环境${NC}"
        return 0
    else
        echo -e "${GREEN}非 CN 网络环境${NC}"
        return 1
    fi
}

# 切换软件源
change_mirrors() {
    echo -e "${YELLOW}[0/5] 配置软件源${NC}"
    
    if detect_region; then
        echo -e "使用阿里云镜像..."
        bash <(curl -sSL https://gitee.com/SuperManito/LinuxMirrors/raw/main/ChangeMirrors.sh) \
          --source mirrors.aliyun.com \
          --protocol http \
          --use-intranet-source false \
          --install-epel true \
          --backup true \
          --upgrade-software false \
          --clean-cache false \
          --ignore-backup-tips \
          --pure-mode
    else
        echo -e "使用官方源..."
        bash <(curl -sSL https://raw.githubusercontent.com/SuperManito/LinuxMirrors/main/ChangeMirrors.sh) \
          --use-official-source true \
          --protocol http \
          --use-intranet-source false \
          --install-epel true \
          --backup true \
          --upgrade-software false \
          --clean-cache false \
          --ignore-backup-tips \
          --pure-mode
    fi
    
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}警告：软件源切换失败，继续使用当前源${NC}"
    else
        apt update -qq
    fi
}

# 二次确认
confirm_operation() {
    echo -e "\n${RED}⚠️  高危操作警告 ⚠️${NC}"
    echo -e "${RED}此脚本将修改系统内核，可能导致：${NC}"
    echo -e "${RED}  • 系统无法启动（如果新内核不兼容）${NC}"
    echo -e "${RED}  • 网络驱动丢失（在特定云平台上）${NC}"
    echo -e "${RED}  • 需要控制台访问权限才能恢复${NC}"
    echo -e "${RED}  • 请务必备份重要数据再执行${NC}"
    echo -e "\n${YELLOW}当前内核：${NC}$(uname -r)"
    echo -e "${YELLOW}虚拟化：${NC}$(systemd-detect-virt 2>/dev/null || echo '未知')"
    
    # 显示将要删除的 Cloud 内核
    local cloud_pkgs=$(dpkg -l 2>/dev/null | awk '/linux-(image|headers)-[0-9].*cloud/ {print $2}')
    if [ -n "$cloud_pkgs" ]; then
        echo -e "\n${YELLOW}将要卸载的 Cloud 内核：${NC}"
        echo "$cloud_pkgs" | sed 's/^/  /'
    fi
    
    echo ""
    read -p "$(echo -e ${YELLOW}"确认继续？[y/N]: "${NC})" confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}操作已取消${NC}"
        exit 0
    fi
    
    echo -e "${GREEN}开始执行...${NC}\n"
}

# 检查当前内核
check_cloud_kernel() {
    if ! uname -r | grep -q 'cloud'; then
        echo -e "${GREEN}提示：系统已在标准内核运行 ($(uname -r))${NC}"
        
        # 检查是否还有 Cloud 内核包
        local cloud_pkgs=$(dpkg -l 2>/dev/null | awk '/linux-(image|headers)-[0-9].*cloud/ {print $2}')
        if [ -n "$cloud_pkgs" ]; then
            echo -e "${YELLOW}但系统中仍有 Cloud 内核包：${NC}"
            echo "$cloud_pkgs" | sed 's/^/  /'
            echo ""
            read -p "$(echo -e ${YELLOW}"是否清理这些包？[y/N]: "${NC})" clean_confirm
            if [[ "$clean_confirm" =~ ^[Yy]$ ]]; then
                apt purge -y $cloud_pkgs
                apt autoremove -y --purge
                update-grub
                echo -e "${GREEN}清理完成${NC}"
            fi
        fi
        exit 0
    fi
}

# 安装标准内核
install_standard_kernel() {
    echo -e "${YELLOW}[1/5] 安装标准内核${NC}"
    
    local image_pkg="linux-image-amd64"
    local headers_pkg="linux-headers-amd64"
    
    if grep -q 'ID=ubuntu' /etc/os-release; then
        image_pkg="linux-image-generic"
        headers_pkg="linux-headers-generic"
    fi
    
    echo -e "正在安装 $image_pkg $headers_pkg ..."
    
    DEBIAN_FRONTEND=noninteractive apt install -y --reinstall \
        "$image_pkg" "$headers_pkg" 2>&1 | grep -E "正在|Setting up|unpacking|Processing|配置|解包"
    
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo -e "${RED}错误：标准内核安装失败！${NC}"
        exit 1
    fi
    
    local std_kernel=$(ls /boot/vmlinuz-* 2>/dev/null | grep -v cloud | sort -V | tail -1 | sed 's|/boot/vmlinuz-||')
    if [ -n "$std_kernel" ]; then
        echo -e "更新 initramfs: $std_kernel"
        update-initramfs -u -k "$std_kernel" 2>&1 | grep -v "^I:"
    fi
    
    echo -e "${GREEN}✓ 标准内核安装完成: $std_kernel${NC}"
}

# 卸载所有 Cloud 内核
remove_cloud_kernels() {
    echo -e "${YELLOW}[2/5] 卸载所有 Cloud 内核${NC}"
    
    # 找出所有 Cloud 内核包（包括 image 和 headers）
    local cloud_pkgs=$(dpkg -l 2>/dev/null | awk '/linux-(image|headers|modules)-[0-9].*cloud/ {print $2}')
    
    if [ -z "$cloud_pkgs" ]; then
        echo -e "${YELLOW}未找到 Cloud 内核包${NC}"
        return 0
    fi
    
    echo -e "正在卸载以下包："
    echo "$cloud_pkgs" | sed 's/^/  /'
    
    # 解锁所有 Cloud 内核
    apt-mark unhold $cloud_pkgs > /dev/null 2>&1
    
    # 彻底卸载
    DEBIAN_FRONTEND=noninteractive apt purge -y $cloud_pkgs 2>&1 | grep -E "正在|Removing|移除|卸载"
    
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo -e "${YELLOW}警告：部分包卸载失败，继续执行...${NC}"
    fi
    
    # 清理残留
    apt autoremove -y --purge > /dev/null 2>&1
    
    # 验证是否清理干净
    local remaining=$(dpkg -l 2>/dev/null | awk '/linux-(image|headers|modules)-[0-9].*cloud/ {print $2}')
    if [ -n "$remaining" ]; then
        echo -e "${YELLOW}警告：以下包未能完全卸载：${NC}"
        echo "$remaining" | sed 's/^/  /'
    else
        echo -e "${GREEN}✓ 所有 Cloud 内核已卸载${NC}"
    fi
}

# 配置 GRUB
configure_grub() {
    echo -e "${YELLOW}[3/5] 配置 GRUB${NC}"
    
    mkdir -p /root/grub_backup
    cp /etc/default/grub /root/grub_backup/grub.default.$(date +%s) 2>/dev/null
    
    # 使用简单的 GRUB_DEFAULT=0
    cat > /etc/default/grub <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX=""
GRUB_DISABLE_OS_PROBER=true
EOF
    
    echo -e "${GREEN}✓ GRUB 配置完成（GRUB_DEFAULT=0）${NC}"
}

# 更新 GRUB
update_grub_config() {
    echo -e "${YELLOW}[4/5] 更新 GRUB${NC}"
    
    cp -a /boot/grub /root/grub_backup/grub.bak.$(date +%s) 2>/dev/null
    
    echo -e "重新生成 GRUB 配置..."
    update-grub 2>&1 | grep -E "Found|Generating|生成|找到"
    
    # 明确设置默认启动项为 0
    grub-set-default 0
    
    if [ -d /sys/firmware/efi ]; then
        echo -e "更新 UEFI 引导..."
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck > /dev/null 2>&1
    fi
    
    echo -e "${GREEN}✓ GRUB 更新完成，默认启动第一个内核${NC}"
}

# 验证配置
verify_configuration() {
    echo -e "${YELLOW}[5/5] 验证配置${NC}"
    
    echo -e "${BLUE}当前内核：${NC}$(uname -r)"
    
    echo -e "${BLUE}系统中的内核：${NC}"
    local all_kernels=$(dpkg -l 2>/dev/null | grep -E 'linux-image-[0-9]' | awk '{print $2}')
    if [ -n "$all_kernels" ]; then
        echo "$all_kernels" | sed 's/^/  /'
    else
        echo "  未找到内核包"
    fi
    
    echo -e "${BLUE}GRUB 启动顺序（前3项）：${NC}"
    awk -F "'" '/menuentry / && $0 !~ /submenu/ {
        count++
        if (count <= 3) {
            print "  " count-1 ": " $2
        }
    }' /boot/grub/grub.cfg 2>/dev/null
    
    echo -e "${BLUE}GRUB 默认设置：${NC}  $(grep "^GRUB_DEFAULT=" /etc/default/grub)"
    
    echo -e "${GREEN}✓ 验证完成${NC}"
}

# 主函数
main() {
    echo -e "\n${GREEN}Debian/Ubuntu 内核切换脚本${NC}\n"
    
    check_root
    check_cloud_kernel
    confirm_operation
    
    change_mirrors
    install_standard_kernel
    remove_cloud_kernels
    configure_grub
    update_grub_config
    verify_configuration
    
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}操作完成！${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "\n${YELLOW}重要提示：${NC}"
    echo -e "  • 所有 Cloud 内核已卸载"
    echo -e "  • 备份位置：${BLUE}/root/grub_backup/${NC}\n"
    
    echo -e "${YELLOW}下一步：${NC}"
    echo -e "  1. 执行 ${BLUE}reboot${NC} 重启系统"
    echo -e "  2. 重启后运行 ${BLUE}uname -r${NC} 确认内核"
    
    read -p "$(echo -e ${YELLOW}"立即重启？[y/N]: "${NC})" reboot_now
    if [[ "$reboot_now" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}正在重启...${NC}"
        sleep 2
        reboot
    fi
}

main "$@"
