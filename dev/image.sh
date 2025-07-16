#!/bin/bash
# Debian/Ubuntu 内核切换脚本
# 功能：从 Cloud 内核切换到标准内核
# 适用：Debian 11+/Ubuntu 18.04+

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：必须使用 root 权限运行此脚本${NC}"
        exit 1
    fi
}

check_cloud_kernel() {
    if ! uname -r | grep -q 'cloud'; then
        echo -e "${GREEN}提示：系统已在标准内核运行 ($(uname -r))${NC}"
        exit 0
    fi
}

purge_cloud_kernel() {
    echo -e "${YELLOW}步骤1/4：彻底移除 Cloud 内核...${NC}"
    
    # 找出所有 Cloud 内核包
    local cloud_pkgs=$(dpkg -l | awk '/linux-(image|headers)-[0-9].*cloud/ {print $2}')
    
    if [ -n "$cloud_pkgs" ]; then
        echo -e "正在卸载: ${cloud_pkgs}"
        apt purge -y $cloud_pkgs
        apt autoremove -y --purge
    else
        echo -e "${GREEN}提示：未找到 Cloud 内核包${NC}"
    fi
}

lock_cloud_kernel() {
    echo -e "${YELLOW}步骤2/4：锁定 Cloud 内核...${NC}"

    # 检查是否还有额外的 Cloud 内核包，如果有则标记为 hold
    cloud_kernels=$(apt list --installed 2>/dev/null | grep -i 'linux-image' | grep -i 'cloud' | cut -d'/' -f1)

    if [ -n "$cloud_kernels" ]; then
        echo "找到以下 Cloud 内核包，正在锁定：$cloud_kernels"
        apt-mark hold $cloud_kernels
    else
        echo -e "${GREEN}提示：未找到任何 Cloud 内核包，跳过锁定步骤。${NC}"
    fi
}

force_install_standard() {
    echo -e "${YELLOW}步骤3/4：安装标准内核...${NC}"
    
    # 根据系统类型选择包名
    local image_pkg="linux-image-amd64"
    local headers_pkg="linux-headers-amd64"
    
    if grep -q 'ID=ubuntu' /etc/os-release; then
        image_pkg="linux-image-generic"
        headers_pkg="linux-headers-generic"
    fi

    # 强制安装并跳过配置提问
    DEBIAN_FRONTEND=noninteractive apt install -y --reinstall --allow-downgrades \
        "$image_pkg" "$headers_pkg"
    
    # 确保 initramfs 更新
    local std_kernel=$(ls /boot/vmlinuz-* | grep -v cloud | sort -V | tail -1 | sed 's|/boot/vmlinuz-||')
    update-initramfs -u -k "$std_kernel"
}

nuclear_grub_update() {
    echo -e "${YELLOW}步骤4/4：重建 GRUB...${NC}"
    
    # 备份原配置
    mkdir -p /root/grub_backup
    cp -a /boot/grub /root/grub_backup/grub.bak.$(date +%s)
    
    # 生成干净的 GRUB 配置
    cat > /etc/default/grub <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=lsb_release -i -s 2> /dev/null || echo Debian
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX=""
GRUB_DISABLE_OS_PROBER=true
GRUB_DISABLE_RECOVERY=true
EOF

    # 完全重建配置
    grub-mkconfig -o /boot/grub/grub.cfg
    
    # 确保使用第一个菜单项
    grub-set-default 0
    update-grub
    
    # 特殊处理 UEFI 系统
    if [ -d /sys/firmware/efi ]; then
        echo -e "检测到 UEFI 系统，更新引导加载程序..."
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck
    fi
}

main() {
    echo -e "\n${GREEN}=== Debian/Ubuntu 内核切换脚本 ===${NC}"   
    check_root
    check_cloud_kernel
    
    # 执行核心修复步骤
    purge_cloud_kernel
    lock_cloud_kernel
    force_install_standard
    nuclear_grub_update
    
    # 最终验证
    echo -e "\n${GREEN}=== 操作完成 ===${NC}"
    echo -e "请手动重启系统："
    echo -e "1. 重启系统: ${YELLOW}reboot${NC}"
    echo -e "2. 检查内核: ${YELLOW}uname -r${NC}"

    touch /root/.kernel_switch_success
}

main "$@"
