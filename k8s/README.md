# k8s环境安装


```
bash <(curl -sSL https://github.com/sky22333/shell/raw/main/k8s/k8s-install.sh)
```

或者脚本安装：https://docs.rke2.io/install/quickstart

管理面板：https://github.com/eip-work/kuboard-press

### 初始化集群（以下步骤仅在主控机上运行）

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
# 查看所有命名空间
kubectl get ns

# 设置默认命名空间
kubectl config set-context --current --namespace=default

# 查看所有节点
kubectl get nodes
kubectl describe node <节点名>   # 查看节点详情

# 查看所有Pod
kubectl get pods                   # 查看当前命名空间下的 Pod
kubectl get pods -A                # 查看所有命名空间的 Pod
kubectl describe pod <pod名>       # 查看Pod详情
kubectl logs <pod名>               # 查看Pod日志
kubectl logs <pod名> -c <容器名>   # 查看某容器日志（Pod内多容器时）
kubectl exec -it <pod名> -- /bin/sh   # 进入Pod容器内部（BusyBox/Alpine）
kubectl exec -it <pod名> -- /bin/bash # 进入Pod容器内部（Ubuntu/Debian）

# 创建资源
kubectl create -f xxx.yaml          # 使用YAML文件创建资源
kubectl apply -f xxx.yaml           # 推荐：应用配置，支持更新已有资源
kubectl delete -f xxx.yaml          # 删除资源
kubectl delete pod <pod名>          # 删除指定Pod
kubectl delete svc <服务名>         # 删除Service
kubectl delete deployment <部署名>  # 删除Deployment

# Deployment 部署相关
kubectl get deployment
kubectl describe deployment <部署名>
kubectl scale deployment <部署名> --replicas=3     # 修改副本数
kubectl rollout status deployment <部署名>         # 查看部署状态
kubectl rollout restart deployment <部署名>        # 重启Deployment
kubectl rollout undo deployment <部署名>           # 回滚到上一个版本

# Service 相关
kubectl get svc                        # 查看所有服务
kubectl describe svc <服务名>
kubectl expose deployment <部署名> --port=80 --target-port=8080 --type=NodePort
# 暴露Deployment为一个Service，外部可通过Node IP访问

# Ingress 相关
kubectl get ingress
kubectl describe ingress <ingress名>
kubectl apply -f ingress.yaml         # 创建Ingress资源

# ConfigMap 和 Secret
kubectl create configmap <名称> --from-literal=KEY=VALUE
kubectl get configmap
kubectl describe configmap <名称>
kubectl create secret generic <名称> --from-literal=KEY=VALUE
kubectl get secret
kubectl describe secret <名称>

# Namespace 命名空间
kubectl create ns <名称>
kubectl delete ns <名称>
kubectl get all -n <名称>             # 查看指定命名空间所有资源

# 资源模板导出
kubectl create deployment nginx --image=nginx --dry-run=client -o yaml > nginx.yaml
# 使用 dry-run 生成资源模板 YAML 文件

# 状态监控类命令
kubectl top nodes                     # 查看节点资源使用情况（需安装 metrics-server）
kubectl top pod                       # 查看 Pod 资源使用情况

# 集群信息
kubectl cluster-info
kubectl version                       # 查看客户端和服务端版本
kubectl config view                   # 查看当前 kubeconfig 配置
kubectl config get-contexts           # 查看所有上下文
kubectl config use-context <名称>     # 切换上下文

# 临时调试容器
kubectl run -it --rm debug --image=busybox --restart=Never -- sh
# 启动一个临时容器，用于调试网络连接等问题
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
