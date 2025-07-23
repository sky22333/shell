#!/bin/bash

# Kubernetes 自动化安装脚本
# 支持 Debian 和 Ubuntu 系统
# 适用于主控机和工作节点

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要 root 权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
}

# 检测操作系统
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        CODENAME=$VERSION_CODENAME
    else
        log_error "无法检测操作系统"
        exit 1
    fi

    case $OS in
        ubuntu)
            log_info "检测到 Ubuntu $VER ($CODENAME)"
            OS_TYPE="ubuntu"
            ;;
        debian)
            log_info "检测到 Debian $VER ($CODENAME)"
            OS_TYPE="debian"
            ;;
        *)
            log_error "不支持的操作系统: $OS"
            log_info "此脚本仅支持 Ubuntu 和 Debian"
            exit 1
            ;;
    esac
}

# 系统准备
prepare_system() {
    log_step "开始系统准备..."
    
    # 禁用 swap
    log_info "禁用 swap..."
    swapoff -a 2>/dev/null || true
    sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    
    # 配置内核模块
    log_info "配置内核模块..."
    cat > /etc/modules-load.d/k8s.conf << EOF
overlay
br_netfilter
EOF
    
    modprobe overlay
    modprobe br_netfilter
    
    # 配置内核参数
    log_info "配置内核参数..."
    cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    
    sysctl --system > /dev/null
    
    # 更新包列表和安装基础工具
    log_info "更新包列表并安装基础工具..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq curl wget lsof gnupg software-properties-common apt-transport-https ca-certificates
    [ -d /etc/apt/sources.list.d ] || mkdir -p /etc/apt/sources.list.d
    log_info "系统准备完成"
}

# 安装 containerd
install_containerd() {
    log_step "安装 containerd 容器运行时..."
    
    # 创建密钥目录
    mkdir -p /etc/apt/keyrings
    
    # 根据系统类型选择合适的仓库
    if [[ $OS_TYPE == "ubuntu" ]]; then
        DOCKER_REPO="ubuntu"
    else
        DOCKER_REPO="debian"
    fi
    
    # 添加 Docker 官方 GPG 密钥
    log_info "添加 Docker GPG 密钥..."
    curl -fsSL https://download.docker.com/linux/$DOCKER_REPO/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # 添加 Docker 仓库
    log_info "添加 Docker 仓库..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DOCKER_REPO $CODENAME stable" > /etc/apt/sources.list.d/docker.list
    
    # 更新包列表并安装 containerd
    log_info "安装 containerd..."
    apt-get update -qq
    apt-get install -y -qq containerd.io
    
    # 配置 containerd
    log_info "配置 containerd..."
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    
    # 启用 SystemdCgroup
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
    
    # 确保 CRI 插件启用（移除 disabled_plugins 中的 cri）
    sed -i '/disabled_plugins.*cri/s/^/#/' /etc/containerd/config.toml
    
    # 启动并启用 containerd
    systemctl restart containerd
    systemctl enable containerd
    
    # 验证 containerd 状态
    if systemctl is-active --quiet containerd; then
        log_info "containerd 安装并启动成功"
    else
        log_error "containerd 启动失败"
        exit 1
    fi
}

# 安装 Kubernetes 组件
install_kubernetes() {
    log_step "安装 Kubernetes 组件..."
    
    # 添加 Kubernetes GPG 密钥
    log_info "添加 Kubernetes GPG 密钥..."
    mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    chmod a+r /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    
    # 添加 Kubernetes 仓库
    log_info "添加 Kubernetes 仓库..."
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' > /etc/apt/sources.list.d/kubernetes.list
    
    # 更新包列表并安装 K8s 组件
    log_info "安装 kubelet, kubeadm, kubectl..."
    apt-get update -qq
    apt-get install -y -qq kubelet kubeadm kubectl
    
    # 锁定版本防止自动更新
    apt-mark hold kubelet kubeadm kubectl
    
    # 启用 kubelet
    systemctl enable kubelet
    
    log_info "Kubernetes 组件安装完成"
}

# 验证安装
verify_installation() {
    log_step "验证安装..."
    
    # 检查 containerd
    if systemctl is-active --quiet containerd; then
        log_info "✓ containerd 运行正常"
    else
        log_error "✗ containerd 未运行"
        return 1
    fi
    
    # 检查 kubelet
    if systemctl is-enabled --quiet kubelet; then
        log_info "✓ kubelet 已启用"
    else
        log_error "✗ kubelet 未启用"
        return 1
    fi
    
    # 检查命令是否可用
    local commands=("kubeadm" "kubelet" "kubectl")
    for cmd in "${commands[@]}"; do
        if command -v $cmd > /dev/null 2>&1; then
            local version=$($cmd version --client=true --short 2>/dev/null | grep -o 'v[0-9.]*' | head -1)
            log_info "✓ $cmd 已安装 ($version)"
        else
            log_error "✗ $cmd 未找到"
            return 1
        fi
    done
    
    # 检查 CRI 是否可用
    if crictl version > /dev/null 2>&1; then
        log_info "✓ CRI 插件可用"
    else
        log_warn "! crictl 不可用，但这不影响基本功能"
    fi
}

# 显示后续步骤
show_next_steps() {
    log_step "安装完成！"
    echo
    log_info "后续步骤:"
    echo "  主控节点初始化:"
    echo "    kubeadm init --pod-network-cidr=10.244.0.0/16 --service-cidr=10.96.0.0/12"
    echo
    echo "  工作节点加入集群:"
    echo "    sudo kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash <hash>"
    echo
    echo "  配置 kubectl (在主控节点上):"
    echo "    mkdir -p \$HOME/.kube"
    echo "    sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config"
    echo "    sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"
    echo
    echo "  安装网络插件 (推荐 Flannel):"
    echo "    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
    echo
}

# 主函数
main() {
    log_info "开始 Kubernetes 自动化安装..."
    echo "支持系统: Ubuntu 和 Debian"
    echo "安装组件: containerd + kubelet + kubeadm + kubectl"
    echo
    
    check_root
    detect_os
    prepare_system
    install_containerd
    install_kubernetes
    
    if verify_installation; then
        show_next_steps
        log_info "脚本执行成功！"
        exit 0
    else
        log_error "安装验证失败，请检查错误信息"
        exit 1
    fi
}

# 脚本入口
main "$@"
