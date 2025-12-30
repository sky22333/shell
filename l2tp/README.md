### L2TP自动安装脚本
```
# 自动安装
l2tp

# 自动安装以及配置透明代理分流规则
l2tp -out

# 卸载服务
l2tp -rm
```

### linux编译
```
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-s -w" -o l2tp
```
### windows编译
```
$env:GOOS="linux"; $env:GOARCH="amd64"; $env:CGO_ENABLED="0"; go build -ldflags="-s -w" -o l2tp
```

### 卸载
```
# 停止服务
systemctl stop xl2tpd strongswan-starter strongswan pptpd 2>/dev/null || true

# 禁用开机自启
systemctl disable xl2tpd strongswan-starter strongswan pptpd 2>/dev/null || true

# 卸载
apt purge -y xl2tpd strongswan pptpd

# 确认是否停止
ps aux | egrep 'xl2tpd|strongswan|pptpd' | grep -v grep
```

### L2TP多用户分流

使用s-ui的`TProxy`入站 透明代理来自L2TP的流量，入站选择`TProxy`，端口`12345`为例，路由规则选择`源IP`，`source_ip_cidr`的IP配置为L2TP的内网来源IP，例如`10.10.10.11`，然后选择对应的出站。

3x-ui则使用`tunnel`入站，打开`Follow Redirect`，打开`Sockopt`中的`TProxy`，然后同样的使用源IP路由到指定出站。

然后使用`iptables`在系统层面拦截`10.10.10.0/24`网段访问公网的流量，交给 Sing-box 处理。