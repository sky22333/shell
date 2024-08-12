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

---
---

## 自托管脚本
- 创建脚本文件
```
mkdir -p /var/www && touch /var/www/shell.sh && chmod 644 /var/www/shell.sh
```

- 一键安装caddy
```
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list && sudo apt update && sudo apt install -y caddy
```
- `/etc/caddy/Caddyfile`写入配置文件

> 也可以直接使用域名
```
http://IP:80 {
    root * /var/www
    file_server
}
```
- 启动运行
```
sudo systemctl restart caddy
```
- 查看状态
```
systemctl status caddy
```
- 停止和卸载
```
sudo systemctl stop caddy && sudo apt-get purge --auto-remove caddy
```


- 用户远程运行脚本
```
bash <(curl -fsSL http://公网IP/shell.sh)
```
---
---

## 脚本加密-编译为可执行文件

- 下载环境
```
sudo apt-get update
sudo apt-get install shc gcc -y
```

- 用法

| 命令                          | 描述                                                              | 示例                                                          |
|-------------------------------|-------------------------------------------------------------------|---------------------------------------------------------------|
| `shc -f <script>`             | 编译指定的 Shell 脚本文件。                                        | `shc -f script.sh`                                             |
| `shc -o <output>`             | 指定输出的可执行文件名。                                          | `shc -f script.sh -o myscript`                                 |
| `shc -e <YYYY-MM-DD>`         | 设置脚本的过期日期，格式为 `YYYY-MM-DD`。                          | `shc -f script.sh -e 2024-12-31`                               |
| `shc -m "<message>"`          | 设置当脚本过期时显示的消息。                                       | `shc -f script.sh -e 2024-12-31 -m "脚本已过期"` |
| `shc -r`                      | 允许在编译后的脚本中保留运行时的环境变量。                        | `shc -r -f script.sh`                                          |
| `shc -T`                      | 不生成中间的 C 源代码文件。                                        | `shc -f script.sh -T`                                          |
| `shc -v`                      | 显示详细信息，帮助调试。                                           | `shc -v -f script.sh`                                          |
| `shc -x`                      | 对脚本中的字符串进行 XOR 加密以增加安全性。                       | `shc -x -f script.sh`                                          |
| `shc -l <lib>`                | 添加特定的库文件链接到编译的二进制文件中。                        | `shc -f script.sh -l /usr/lib/somelibrary.so`                  |

- 远程执行加密脚本
```
curl -fsSL http://公网IP/my.sh -o my.sh && chmod +x my.sh && ./my.sh
```
需要系统一致

---
---
