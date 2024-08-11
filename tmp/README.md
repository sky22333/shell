### 自用批量搭建节点并把节点信息传输到另一台机器

一：先在脚本变量中填入目标服务器信息

二：目标主机需在`home`目录下创建`xray.txt`文件
```
touch /home/xray.txt
```
三：然后再执行此脚本

```
bash <(wget -qO- https://github.com/sky22333/shell/raw/main/tmp/ss.sh)
```

---

- 其他命令

```
# 查看 Xray 状态
systemctl status xray

# 停止 Xray 服务
systemctl stop xray

# 禁用 Xray 服务和开机自启
systemctl disable xray

# 删除 Xray 二进制文件
rm -f /usr/local/bin/xray

# 删除 Xray 配置文件及相关目录
rm -rf /usr/local/etc/xray
```


### 自托管脚本
创建脚本文件
```
mkdir -p /var/www && touch /var/www/shell.sh && chmod 644 /var/www/shell.sh
```

一键安装caddy
```
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list && sudo apt update && sudo apt install -y caddy
```
`/etc/caddy/Caddyfile`写入配置文件

#可以直接使用域名
```
http://IP:80 {
    root * /var/www
    file_server
}
```
启动运行
```
sudo systemctl restart caddy
```
查看状态
```
systemctl status caddy
```
停止和卸载
```
sudo systemctl stop caddy && sudo apt-get purge --auto-remove caddy
```


用户远程运行脚本
```
bash <(curl -fsSL http://公网IP/shell.sh)
```
