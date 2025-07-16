### 一键安装ansible

见 [ansible.md](./ansible.md)

---

### 常用运维脚本

- 一键切换系统源脚本
```
bash <(curl -sSL https://github.com/sky22333/shell/raw/main/dev/mirrors.sh)
```
- 切换官方系统源
```
bash <(curl -sSL https://github.com/sky22333/shell/raw/main/dev/mirrors.sh) --use-official-source true
```

- 一键安装Docker和配置镜像地址
```
bash <(curl -sSL https://github.com/sky22333/shell/raw/main/dev/docker.sh)
```


- acme.sh 证书一键申请脚本

```
bash <(curl -sSL https://github.com/sky22333/shell/raw/main/dev/acme.sh)
```


- Linux切换到标准内核：
```
bash <(curl -sSL https://github.com/sky22333/shell/raw/main/dev/image.sh)
```

- 一键安装go环境：
```
bash <(curl -sSL https://github.com/sky22333/shell/raw/main/dev/go.sh)
```


- 一键启用BBR：
```
bash <(curl -sSL https://github.com/sky22333/shell/raw/main/dev/bbr.sh)
```

- 一键内网穿透(无需域名和服务器)：
```
bash <(curl -sSL https://github.com/sky22333/shell/raw/main/dev/cf-tunnel.sh)
```

- `win`系统`PowerShell`在线脚本，需要以管理员模式打开`PowerShell`
```
iwr -useb https://ghproxy.net/https://raw.githubusercontent.com/sky22333/shell/main/dev/cf-setup.ps1 | iex
```
