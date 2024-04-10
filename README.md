###  acme.sh 证书一键申请脚本



```
wget -N --no-check-certificate https://github.com/taotao1058/shell/raw/main/acme.sh && bash acme.sh
```


###  一键搭建LNMP环境的WordPress脚本

适用于Ubuntu系统。（需先把域名解析到公网IP并开放80和443端口用于自动配置TLS证书）

```
wget -N --no-check-certificate https://github.com/taotao1058/shell/raw/main/wordpress.sh && bash wordpress.sh
```


###  快速批量搭建二级代理脚本

适用于Debian、Ubuntu、Kali Linux 系统。xray内核 vmess入站，多sk5出站

```
wget -N --no-check-certificate https://github.com/taotao1058/shell/raw/main/vmess.sh && bash vmess.sh
```

### Hysteria 2 一键搭建脚本

```
wget -N --no-check-certificate https://raw.githubusercontent.com/taotao1058/shell/main/hy2/hysteria.sh && bash hysteria.sh
```

###  reality一键脚本



```
wget -N --no-check-certificate https://github.com/taotao1058/shell/raw/main/reality.sh && bash reality.sh
```

### vmess+ws一键脚本
```
wget -N --no-check-certificate https://github.com/taotao1058/shell/raw/main/xray.sh && bash xray.sh
```

### 批量搭建vmess节点并把节点信息传输到另一台机器

一：先把`x.sh`文件中的第88行填入你目的主机的密码和IP

二：目的主机需在`home`目录下创建`xray.txt`文件
```
touch /home/xray.txt
```
三：然后再执行此脚本

```
wget -N --no-check-certificate https://github.com/taotao1058/shell/raw/main/x.sh && bash x.sh
```

### 批量管理多台服务器脚本

先在`root`目录下创建`ssh.txt`文件，文件内填入服务器信息，每行一个服务器，每行包含四部分信息（IP地址、端口、用户名和密码），用空格分隔。
```
wget -N --no-check-certificate https://github.com/taotao1058/shell/raw/main/ssh.sh && bash ssh.sh
```


###  端口限速脚本



```
wget -N --no-check-certificate https://github.com/taotao1058/shell/raw/main/Mbit.sh && bash Mbit.sh
```
