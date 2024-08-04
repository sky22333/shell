###  acme.sh 证书一键申请脚本




```
bash <(wget -qO- https://github.com/sky22333/shell/raw/main/acme.sh)
```

###  一键搭建LNMP环境的WordPress脚本

适用于Ubuntu系统。（需先把域名解析到公网IP并开放80和443端口用于自动配置TLS证书）


```
bash <(wget -qO- https://github.com/sky22333/shell/raw/main/wordpress.sh)
```

###  快速批量搭建二级代理脚本

适用于Debian、Ubuntu、Kali Linux 系统。xray内核 vmess入站，多sk5出站


```
bash <(wget -qO- https://github.com/sky22333/shell/raw/main/vmess.sh)
```

### Hysteria 2 一键搭建脚本


```
bash <(wget -qO- https://github.com/sky22333/shell/raw/main/hy2/hysteria.sh)
```

### sing-box一键脚本（多协议）
```
bash <(wget -qO- -o- https://github.com/admin8800/sing-box/raw/main/install.sh)
```
#### 使用`sing-box`查看管理菜单

### vmess+ws一键脚本

```
bash <(wget -qO- https://github.com/sky22333/shell/raw/main/xray.sh)
```

### 批量搭建vmess节点并把节点信息传输到另一台机器

一：先把`x.sh`文件中的第88行填入你目的主机的密码和IP

二：目的主机需在`home`目录下创建`xray.txt`文件
```
touch /home/xray.txt
```
三：然后再执行此脚本

```
bash <(wget -qO- https://github.com/sky22333/shell/raw/main/x.sh)
```


###  端口限速脚本

```
bash <(wget -qO- https://github.com/sky22333/shell/raw/main/Mbit.sh)
```


###  一键安装Docker和Docker compose

```
bash <(wget -qO- https://github.com/sky22333/shell/raw/main/kaiji.sh)
```