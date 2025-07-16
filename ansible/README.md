### 1：Ansibler容器环境搭建

#### 运行示例
```
docker run --rm -it \
  -v ./ansible:/etc/ansible \
  -w /etc/ansible \
  ghcr.io/sky22333/shell:ansible \
  ansible-playbook renwu.yml
```


| 参数 | 作用 |
|------|------|
| `docker run` | 启动一个容器运行指定镜像 |
| `--rm` | 容器退出后自动删除（保持系统干净） |
| `-it` | 启用交互终端模式，允许输出彩色日志和提示信息 |
| `-v ./ansible:/etc/ansible` | 把你本地的 `./ansible` 目录挂载到容器的 `/etc/ansible` 路径下 |
| `-w /etc/ansible` | 设置容器的工作目录为 `/etc/ansible`，也就是你挂载的目录 |
| `ghcr.io/sky22333/shell:ansible` | 使用此镜像，预装了 ansible |
| `ansible-playbook renwu.yml` | 容器中执行的命令，也就是运行挂载进去的 `renwu.yml` 剧本文件 |




#### ansible 目录结构
```
.
├── ansible/
│   ├── renwu.yml
│   ├── hosts
│   └── ansible.cfg
```


`ansible`有如下示例配置

> `ansible.cfg` 配置Ansible的全局设置。

> `hosts` 定义要管理的主机和主机组。

> `renwu.yml（或playbook）` 描述要在主机上执行的任务和操作步骤。



---
---


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
  become: yes   
  tasks:
    - name: 更新包列表
      apt:
        update_cache: yes

    - name: 安装所需的软件包
      apt:
        name:
          - curl
          - wget
          - zip
          - tar
        state: present

    - name: 将脚本复制到远程主机
      copy:
        # 本地脚本路径
        src: /etc/ansible/ss.sh
        # 远程主机上的目标路径
        dest: /tmp/ss.sh  
        # 设置脚本权限为可执行
        mode: '0755'  

    - name: 在远程主机上执行脚本
      shell: /tmp/ss.sh  # 在远程主机上执行脚本
```


或者直接执行远程脚本示例
```
---
# 定义要执行任务的主机组
- hosts: myservers
  become: yes  # 以管理员权限运行命令
  tasks:
    - name: 更新包列表
      apt:
        update_cache: yes

    - name: 安装所需的软件包
      apt:
        name:
          - curl
          - wget
          - zip
          - tar
        state: present

    - name: 在被控主机上执行远程脚本
      shell: bash <(wget -qO- https://github.com/user/shell/raw/main/dev.sh)
      args:
        executable: /bin/bash  # 确保使用bash执行命令
```

### 6：用法示例

- 对所有被控机器运行`renwu.yml`中的任务
```
ansible-playbook renwu.yml
```

- 临时对所有主机执行普通命令
```
ansible all -a "pwd"
```
- 临时对所有主机运行远程脚本
```
ansible all -m shell -a "bash <(wget -qO- https://github.com/user/shell/raw/main/dev.sh)"
```
- 临时将本地脚本复制给所有被控主机并执行
```
ansible all -m copy -a "src=/etc/ansible/script.sh dest=/tmp/script.sh mode=0755"
ansible all -m shell -a "/tmp/script.sh"
```
- 临时对1，3号主机执行shell命令
```
ansible 1,3 -m shell -a "你的命令"
```
- 临时对1，3号主机执行普通命令
```
ansible 1,3 -a "pwd"
```
> 命令结尾后面追加`-v`选项会显示被控机器详细的执行信息

---

#### 命令解释
> `-m` 用于指定 Ansible 模块
 
> `-a` 用于指定传递给模块的参数或命令

| 模块              | 指令    | 中文解释                                     | 用法示例                                          |
|-------------------|---------|----------------------------------------------|---------------------------------------------------|
| `shell`           | `-a`    | 执行 shell 命令。支持管道、重定向等 shell 特性。 | `ansible all -m shell -a "pwd"`                  |
| `command`         | `-a`    | 执行命令，不通过 shell。默认模块                     | `ansible all -m command -a "ls -l"`              |
| `copy`            | `-a`    | 复制文件或目录到目标主机。                    | `ansible all -m copy -a "src=/local/file dest=/remote/file mode=0644"` |
| `file`            | `-a`    | 管理文件和目录的属性（如权限、所有权等）。    | `ansible all -m file -a "path=/remote/file state=absent"` |
| `yum`             | `-a`    | 使用 Yum 包管理器安装、更新或删除软件包（适用于 RHEL/CentOS）。 | `ansible all -m yum -a "name=nginx state=present"` |
| `apt`             | `-a`    | 使用 APT 包管理器安装、更新或删除软件包（适用于 Debian/Ubuntu）。 | `ansible all -m apt -a "name=nginx state=latest"` |
| `service`         | `-a`    | 管理服务（如启动、停止、重启服务）。         | `ansible all -m service -a "name=nginx state=started"` |
| `systemd`         | `-a`    | 管理 systemd 服务（如启动、停止、重启服务）。| `ansible all -m systemd -a "name=nginx state=started"` |
| `user`            | `-a`    | 管理用户账户（如创建、删除用户）。           | `ansible all -m user -a "name=alice state=present"` |
| `group`           | `-a`    | 管理用户组（如创建、删除组）。               | `ansible all -m group -a "name=admin state=present"` |
| `git`             | `-a`    | 管理 Git 仓库（如克隆、拉取、提交等）。      | `ansible all -m git -a "repo=https://github.com/user/repo.git dest=/path/to/repo"` |
| `template`        | `-a`    | 使用 Jinja2 模板引擎渲染模板文件。            | `ansible all -m template -a "src=template.j2 dest=/etc/config"` |
| `cron`            | `-a`    | 管理 cron 任务。                             | `ansible all -m cron -a "name='Backup' minute='0' hour='2' job='/usr/bin/backup.sh'"` |
| `wait_for`        | `-a`    | 等待某个条件满足（如端口开放、文件存在等）。 | `ansible all -m wait_for -a "port=80 delay=10 timeout=300"` |
| `docker_container`| `-a`    | 管理 Docker 容器（如启动、停止、删除容器）。 | `ansible all -m docker_container -a "name=my_container state=started"` |
| `docker_image`    | `-a`    | 管理 Docker 镜像（如拉取、删除镜像）。      | `ansible all -m docker_image -a "name=nginx tag=latest state=present"` |
| `lineinfile`      | `-a`    | 在文件中插入、删除或修改行。               | `ansible all -m lineinfile -a "path=/etc/hosts line='127.0.0.1 localhost' state=present"` |
| `ini_file`        | `-a`    | 修改 INI 配置文件。                         | `ansible all -m ini_file -a "path=/etc/myconfig.ini section=database option=host value=localhost"` |
| `debug`           | `-a`    | 打印调试信息。                               | `ansible all -m debug -a "msg='This is a debug message'"` |



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
