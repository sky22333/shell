##  VPS一键DD 重装系统


# Tools版本

[脚本原地址](https://github.com/leitbogioro/Tools)

#### 先下载
```
cd /root
```

```
wget --no-check-certificate -qO InstallNET.sh 'https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh' && chmod a+x InstallNET.sh
```

#### 国内环境下载
```
wget --no-check-certificate -qO InstallNET.sh 'https://gitee.com/mb9e8j2/Tools/raw/master/Linux_reinstall/InstallNET.sh' && chmod a+x InstallNET.sh
```

### 运行
```
bash InstallNET.sh -debian 11
```

### 运行结尾传递参数

选择越新的系统越需要较高的配置

`-debian 7-12` Debian 7 及更高版本


`-kali Rolling/dev/experimental` Kali Rolling，开发和实验，推荐Kali Rolling

`-centos 7-9` CentOS 7 及更高版本

`-alpine 3.16-3.18/edge` Alpine Linux 3.16 及更高版本，轻量级系统，为了保持更新到最新版本，推荐edge

`-almalinux/alma 8/9`  AlmaLinux 8 及更高版本


`-ubuntu 20.04/22.04/24.04` 不稳定，可能失败


`-windows 10/11/2012/2016/2019/2022` 需4H4G以上，且不支持回退

`-pwd "密码"`   指定密码

### 默认信息

默认用户名

对于 Linux：`root`

对于 Windows：`Administrator`

默认密码

对于 Linux：`LeitboGi0ro`

对于 Windows：`Teddysun.com`

默认端口

对于Linux：`与之前的系统相同`

对于 Windows：`3389`


---



# reinstall版本

[项目地址](https://github.com/bin456789/reinstall)


国外服务器：

```
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh
```

国内服务器：

```
curl -O https://cnb.cool/bin456789/reinstall/-/git/raw/main/reinstall.sh
```

## Linux使用示例

1. 安装Debian12
```
chmod +x reinstall.sh && ./reinstall.sh debian 12
```
2. 设置密码
3. 重启开始安装
```
reboot
```

### 功能 : 安装Linux

- 用户名 `root` 默认密码 `123@@@`
- 安装最新版可不输入版本号
- 最大化利用磁盘空间：不含 boot 分区（Fedora 例外），不含 swap 分区
- 自动根据机器类型选择不同的优化内核，例如 `Cloud`、`HWE` 内核
- 安装 Red Hat 时需填写 <https://access.redhat.com/downloads/content/rhel> 得到的 `qcow2` 镜像链接，也可以安装其它类 RHEL 系统，例如 `Alibaba Cloud Linux` 和 `TencentOS Server`
- 重装后如需修改 SSH 端口或者改成密钥登录，注意还要修改 `/etc/ssh/sshd_config.d/` 里面的文件

```bash
bash reinstall.sh anolis      7|8|23
                  opencloudos 8|9|23
                  rocky       8|9
                  redhat      8|9   --img="http://xxx.com/xxx.qcow2"
                  oracle      8|9
                  almalinux   8|9
                  centos      9|10
                  fedora      40|41
                  nixos       24.11
                  debian      9|10|11|12
                  opensuse    15.6|tumbleweed
                  alpine      3.18|3.19|3.20|3.21
                  openeuler   20.03|22.03|24.03|24.09
                  ubuntu      16.04|18.04|20.04|22.04|24.04|24.10 [--minimal]
                  kali
                  arch
                  gentoo
                  aosc
                  fnos
```

#### 可选参数

- `--password PASSWORD` 设置密码
- `--ssh-key KEY` 设置 SSH 登录公钥，支持以下格式。当使用公钥时，密码为空
  - `--ssh-key "ssh-rsa ..."`
  - `--ssh-key "ssh-ed25519 ..."`
  - `--ssh-key "ecdsa-sha2-nistp256/384/521 ..."`
  - `--ssh-key http://path/to/public_key`
  - `--ssh-key github:your_username`
  - `--ssh-key gitlab:your_username`
  - `--ssh-key /path/to/public_key`
  - `--ssh-key C:\path\to\public_key`
- `--ssh-port PORT` 修改 SSH 端口（安装期间观察日志用，也作用于新系统）
- `--web-port PORT` 修改 Web 端口（安装期间观察日志用）
- `--hold 2` 安装结束后不重启，此时可以 SSH 登录修改系统内容，系统挂载在 `/os` (此功能不支持 Debian/Kali)

> [!TIP]
> 安装 Debian/Kali 时，x86 可通过后台 VNC 查看安装进度，ARM 可通过串行控制台查看安装进度。
>
> 安装其它系统时，可通过多种方式（SSH、HTTP 80 端口、后台 VNC、串行控制台）查看安装进度。
> <br />即使安装过程出错，也能通过 SSH 运行 `/trans.sh alpine` 安装到 Alpine。