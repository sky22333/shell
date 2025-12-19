#### L2TP自动安装脚本
```
curl -sSL https://cdn.jsdelivr.net/gh/sky22333/shell@main/l2tp/l2tp -o /usr/local/bin/l2tp && chmod +x /usr/local/bin/l2tp
```
```
l2tp
```

#### linux编译
```
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags="-s -w" -o l2tp
```
#### windows编译
```
$env:GOOS="linux"; $env:GOARCH="amd64"; $env:CGO_ENABLED="0"; go build -ldflags="-s -w" -o l2tp
```


#### 卸载
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
