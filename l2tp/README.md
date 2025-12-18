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
