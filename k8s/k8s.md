# k8s环境安装


```
bash <(curl -sSL https://github.com/sky22333/shell/raw/main/k8s/k8s-install.sh)
```



### 初始化集群（以下步骤仅在控制机上运行）

运行命令
```bash
kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --service-cidr=10.96.0.0/12 \
```
等待拉取镜像完成


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
```

查看网络状态
```
kubectl get pods -n kube-flannel -o wide
```

## 安装Helm

```bash
# 安装Helm
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" > /etc/apt/sources.list.d/helm-stable-debian.list

apt update && apt install -y helm

# 验证Helm安装
helm version
```

## 安装traefik

traefik 是反向代理和证书管理工具：

```bash
# 添加 Traefik Helm 仓库
helm repo add traefik https://traefik.github.io/charts
helm repo update

# 创建 traefik 命名空间
kubectl create namespace traefik

# 安装 Traefik
helm install traefik traefik/traefik \
  --namespace traefik --create-namespace \
  --set deployment.replicas=1 \
  --set service.type=LoadBalancer \
  --set ports.websecure.tls=true \
  --set ingressClass.enabled=true \
  --set ingressClass.isDefaultClass=true

# 验证 Traefik 安装
kubectl get pods -n traefik
```

## 常用操作命令

```bash
# 查看集群状态
kubectl cluster-info
kubectl get nodes
kubectl get pods -A

# 查看Ingress
kubectl get ingress -A

# 重启部署
kubectl rollout restart deployment/<deployment-name>

# 查看资源使用
kubectl top nodes
kubectl top pods -A
```

## 地址说明
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


### 如果启动失败需要重新运行（可选）
```
sudo kubeadm reset -f
sudo rm -r /etc/kubernetes/ ~/.kube/ /var/lib/etcd/ /etc/cni/net.d/
sudo systemctl restart containerd
```
然后重新初始化集群
