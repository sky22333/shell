### 批量搭建节点并把节点信息传输到另一台机器

一：先在脚本变量中填入目标服务器信息

二：目的主机需在`home`目录下创建`xray.txt`文件
```
touch /home/xray.txt
```
三：然后再执行此脚本

```
bash <(wget -qO- https://github.com/sky22333/shell/raw/main/tmp/shadowsocks.sh)
```