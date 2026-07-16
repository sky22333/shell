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

路由规则选择`源IP`，`source_ip_cidr`的IP配置为L2TP的内网来源IP，例如`10.10.10.11`，然后选择对应的出站。

### singbox 1.40+
```
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "type": "udp",
        "tag": "dns-direct",
        "server": "223.5.5.5"
      },
      {
        "type": "https",
        "tag": "dns-remote",
        "server": "1.1.1.1",
        "server_port": 443,
        "path": "/dns-query",
        "detour": "proxy",
        "domain_resolver": "dns-direct"
      }
    ],
    "rules": [
      {
        "source_ip_cidr": ["10.10.10.0/24"],
        "action": "route",
        "server": "dns-remote"
      }
    ],
    "final": "dns-direct",
    "strategy": "ipv4_only"
  },
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "tun0",
      "address": ["172.19.0.1/30"],
      "mtu": 1500,
      "stack": "mixed",
      "dns_mode": "hijack",
      "dns_address": ["172.19.0.2"],
      "auto_route": true,
      "auto_redirect": true,
      "strict_route": true,
      "route_exclude_address": ["10.10.10.0/24"]
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "anytls",
      "tag": "proxy",
      "server": "8.8.8.8",
      "server_port": 8443,
      "password": "iAq43123123",
      "idle_session_check_interval": "30s",
      "idle_session_timeout": "30s",
      "min_idle_session": 5,
      "tls": {
        "enabled": true,
        "server_name": "bing.com",
        "insecure": true
      },
      "domain_resolver": "dns-direct"
    }
  ],
  "route": {
    "rules": [
      {
        "port": [53],
        "action": "hijack-dns"
      },
      {
        "source_ip_cidr": ["10.10.10.0/24"],
        "invert": true,
        "action": "bypass"
      },
      {
        "ip_is_private": true,
        "action": "route",
        "outbound": "direct"
      },
      {
        "source_ip_cidr": ["10.10.10.0/24"],
        "action": "route",
        "outbound": "proxy"
      }
    ],
    "final": "direct",
    "auto_detect_interface": true,
    "default_domain_resolver": {
      "server": "dns-direct"
    }
  }
}
```
