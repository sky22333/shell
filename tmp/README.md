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

## 🔵自托管脚本
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

## 🔵脚本加密-编译为可执行文件

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

## 🔵ansible批量管理主机运维工具

- ### ✨一键安装脚本
  
```
bash <(wget -qO- https://github.com/sky22333/shell/raw/main/tmp/ansible.sh)
```
 
### 1：安装并创建配置文件
```
sudo apt update
sudo apt install ansible -y
```
```
mkdir -p /etc/ansible && cd /etc/ansible && touch ansible.cfg hosts renwu.yml
```

> `ansible.cfg` 配置Ansible的全局设置。

> `hosts` 定义要管理的主机和主机组。

> `renwu.yml（或playbook）` 描述要在主机上执行的任务和操作步骤。

### 2：禁用被控主机密钥检查

`ansible.cfg`中添加以下配置
```
[defaults]
host_key_checking = False
ansible_ssh_common_args = '-o StrictHostKeyChecking=no'
```


### 3：配置被控主机清单


`hosts`中添加被控主机示例
```
[myservers]
1 ansible_host=192.168.1.1 ansible_user=root ansible_port=22 ansible_ssh_pass=password1
2 ansible_host=192.168.1.2 ansible_user=root ansible_port=22 ansible_ssh_pass=password2
3 ansible_host=192.168.1.3 ansible_user=root ansible_port=22 ansible_ssh_pass=password3
4 ansible_host=192.168.1.4 ansible_user=root ansible_port=22 ansible_ssh_pass=password4
5 ansible_host=192.168.1.5 ansible_user=root ansible_port=22 ansible_ssh_pass=password5
```

### 4：使用ping模块测试所有被控主机连通性


> (可选)查看所有被控机的信息 `ansible-inventory --list -i /etc/ansible/hosts`


```
ansible -m ping all
```

### 5：创建被控主机任务配置文件

`renwu.yml`中添加任务示例

```
---
# 定义要执行任务的主机组
- hosts: myservers
  become: yes  # 以管理员权限运行命令
  tasks:
    - name: 将Shell脚本复制到远程主机
      copy:
        # 本地脚本路径
        src: /etc/ansible/script.sh  
        # 远程主机上的目标路径
        dest: /tmp/script.sh  
        # 设置脚本权限为可执行
        mode: '0755'  

    - name: 在远程主机上执行Shell脚本
      shell: /tmp/script.sh  # 在远程主机上执行脚本
```


或者直接执行远程脚本示例
```
---
# 定义要执行任务的主机组
- hosts: myservers
  become: yes  # 以管理员权限运行命令
  tasks:
    - name: 更新包列表并安装所需的软件包
      shell: |
        apt update
        apt install curl wget git zip tar lsof -y

    - name: 在远程主机上执行Shell脚本
      shell: bash <(wget -qO- https://github.com/sky22333/shell/raw/main/vmess-ws.sh)
      args:
        executable: /bin/bash  # 确保使用bash执行命令
```

### 6：运行任务，需要在`renwu.yml`同目录运行
```
ansible-playbook renwu.yml
```

临时对所有主机执行命令
```
ansible all -a "ls"
```


---
---

#### 执行结果解释
- **ok**: 表示在该主机上成功完成的任务数。
- **changed**: 表示在该主机上有多少任务进行了更改（如文件被复制、脚本被执行）。
- **unreachable**: 表示无法连接的主机数量。
- **failed**: 表示任务失败的数量。
- **skipped**: 表示被跳过的任务数量。
- **rescued**: 表示在任务失败后被恢复的数量。
- **ignored**: 表示被忽略的任务数量。
- 绿色：任务顺利完成
- 橙色：任务执行后有变化，比如文件被修改或某些服务被重启。
- 红色：任务执行失败，一般会终止剩余的所有任务。


#### 如果所有被控机端口和密码都一样
`/etc/ansible/hosts`配置可以这样写
```
[all:vars]
ansible_user=root
ansible_ssh_pass=your_password
ansible_port=22

[myservers]
1 ansible_host=192.168.1.101
2 ansible_host=192.168.1.102
3 ansible_host=192.168.1.103
```
