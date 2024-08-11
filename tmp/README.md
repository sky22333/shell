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
# 停止 Xray 服务
systemctl stop xray

# 禁用 Xray 服务和开机自启
systemctl disable xray

# 删除 Xray 二进制文件
rm -f /usr/local/bin/xray

# 删除 Xray 配置文件及相关目录
rm -rf /usr/local/etc/xray
```
