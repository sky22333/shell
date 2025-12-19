### L2TP自动安装脚本
```
curl -sSL https://cdn.jsdelivr.net/gh/sky22333/shell@main/l2tp/l2tp -o /usr/local/bin/l2tp && chmod +x /usr/local/bin/l2tp
```
```
l2tp
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

**然后使用`iptables`在系统层面拦截`10.10.10.0/24`网段访问公网的流量，交给 Sing-box 处理，按照以下步骤配置**

1：配置 Linux 内核策略路由，将打标流量重定向到本地。
```
# 配置策略路由：凡是防火墙标记 (fwmark) 为 1 的流量，查路由表 100
/bin/ip rule add fwmark 1 table 100

# 配置路由表 100：将所有流量重定向到本地回环接口
/bin/ip route add local 0.0.0.0/0 dev lo table 100
```

2：新建一个链 SINGBOX
```
iptables -t mangle -N SINGBOX
```

3：绕过局域网和私有地址（不代理内部通信）
```
iptables -t mangle -A SINGBOX -d 0.0.0.0/8 -j RETURN
iptables -t mangle -A SINGBOX -d 10.0.0.0/8 -j RETURN
iptables -t mangle -A SINGBOX -d 127.0.0.0/8 -j RETURN
iptables -t mangle -A SINGBOX -d 169.254.0.0/16 -j RETURN
iptables -t mangle -A SINGBOX -d 172.16.0.0/12 -j RETURN
iptables -t mangle -A SINGBOX -d 192.168.0.0/16 -j RETURN
iptables -t mangle -A SINGBOX -d 224.0.0.0/4 -j RETURN
iptables -t mangle -A SINGBOX -d 240.0.0.0/4 -j RETURN
```

4：核心拦截规则：仅拦截来自 L2TP 网段`10.10.10.0/24`的流量，TProxy 端口为`12345`
```
iptables -t mangle -A SINGBOX -s 10.10.10.0/24 -p tcp -j TPROXY --on-port 12345 --tproxy-mark 1
iptables -t mangle -A SINGBOX -s 10.10.10.0/24 -p udp -j TPROXY --on-port 12345 --tproxy-mark 1
```

5：应用到 PREROUTING 链
```
iptables -t mangle -A PREROUTING -j SINGBOX
```

6：不允许公网访问透明代理端口
```
iptables -I INPUT -p tcp --dport 12345 -j DROP
iptables -I INPUT -p udp --dport 12345 -j DROP
```

#### 清理流量规则（按顺序执行）
```
# 清理 iptables 规则
iptables -t mangle -D PREROUTING -j SINGBOX
iptables -t mangle -F SINGBOX
iptables -t mangle -X SINGBOX
```
```
# 清理策略路由和路由表
/bin/ip route del local 0.0.0.0/0 dev lo table 100
/bin/ip rule del fwmark 1 table 100
```
```
# 放行透明代理端口
iptables -D INPUT -p tcp --dport 12345 -j DROP
iptables -D INPUT -p udp --dport 12345 -j DROP
```
