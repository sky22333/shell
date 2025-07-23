# k8s环境安装


```
bash <(curl -sSL https://github.com/sky22333/shell/raw/main/k8s/k8s-instal.sh)
```
## 环境安装（以下步骤主控机和节点集群都需要执行）

```bash
cat <<'EOF' > k8s-prep.sh
#!/bin/bash
set -e

# 禁用swap
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 配置内核模块和参数
cat <<MODULES > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
MODULES

modprobe overlay
modprobe br_netfilter

cat <<SYSCTL > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
SYSCTL

sysctl --system

apt update && apt install -y curl wget lsof gnupg
echo "系统准备完成"
EOF

chmod +x k8s-prep.sh
sudo ./k8s-prep.sh
```

## 安装容器运行时 (containerd)

```bash
# 安装containerd
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt update && apt install -y containerd.io

# 配置containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd
```

## 安装Kubernetes组件

```bash
# 添加K8s官方仓库
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.33/deb/ /' > /etc/apt/sources.list.d/kubernetes.list

# 安装K8s组件
apt update && apt install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable --now kubelet
```

## 启用 CRI 插件
编辑`/etc/containerd/config.toml`文件

去掉或注释这一行：
```
disabled_plugins = ["cri"]
```

重启containerd服务
```
systemctl restart containerd
```


---
---
---




# 初始化集群（以下步骤仅在控制机上运行）

地址说明
```
# 使用网卡上真实存在的内网IP
# API Server绑定到这个地址
--apiserver-advertise-address=内网IP
```
```
# 在TLS证书中添加公网IP
# 允许通过公网IP访问API Server
# 同时保留内网IP访问能力
--apiserver-cert-extra-sans=内网IP,公网IP
```

运行命令
```bash
kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --service-cidr=10.96.0.0/12 \
  --apiserver-advertise-address=YOUR_IP
  --apiserver-cert-extra-sans=YOUR_IP,公网IP
```
等待拉取镜像完成


### 如果启动失败需要重新运行（可选）
```
sudo kubeadm reset -f
sudo rm -r /etc/kubernetes/ ~/.kube/ /var/lib/etcd/ /etc/cni/net.d/
sudo systemctl restart containerd
```
然后重新初始化集群


### 移动配置到用户目录
```
rm -f $HOME/.kube/config
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

## 安装网络插件 (Flannel)

```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# 等待网络插件就绪
kubectl wait --for=condition=ready pod -l app=flannel -n kube-flannel --timeout=300s
```

## 注意！

在输出的命令中，需要替换成公网IP，再在node节点集群中执行


## 安装Helm

```bash
# 安装Helm
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" > /etc/apt/sources.list.d/helm-stable-debian.list

apt update && apt install -y helm

# 验证Helm安装
helm version
```

## 安装cert-manager

cert-manager是生产环境必需的TLS证书管理工具：

```bash
# 添加cert-manager Helm仓库
helm repo add jetstack https://charts.jetstack.io
helm repo update

# 创建cert-manager命名空间
kubectl create namespace cert-manager

# 安装cert-manager (包含CRDs)
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.18.2 \
  --set crds.enabled=true \
  --set global.leaderElection.namespace=cert-manager

# 验证cert-manager安装
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
kubectl get pods -n cert-manager
```

## 配置Let's Encrypt证书颁发者
创建生产环境ClusterIssuer
```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com  # 替换为你的邮箱
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```


## 常用操作命令

```bash
# 查看集群状态
kubectl cluster-info
kubectl get nodes
kubectl get pods -A

# 查看证书状态
kubectl get certificates -A
kubectl describe certificate <cert-name>

# 查看Ingress
kubectl get ingress -A

# 重启部署
kubectl rollout restart deployment/<deployment-name>

# 查看资源使用
kubectl top nodes
kubectl top pods -A
```
