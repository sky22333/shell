## openclaw (原 ClawdBot) 一键安装与管理脚本

### linux 脚本
```
bash <(curl -sSL https://raw.githubusercontent.com/sky22333/shell/main/openclaw/install.sh)
```

### mac 脚本
```
bash <(curl -sSL https://raw.githubusercontent.com/sky22333/shell/main/openclaw/install_mac.sh)
```

### windows 脚本
直接下载使用编译好的二进制文件：https://github.com/sky22333/shell/raw/main/openclaw/installer/installer.exe

下载后使用管理员权限运行

CMD修改加速域名环境变量（可选）
```
set GIT_PROXY=https://g.blfrp.cn/
```

### 构建（可选）
如果你不放心预编译的二进制文件，可以自己构建。

1：windows 安装go环境：https://golang.org/doc/install

2：进入项目目录
```
cd openclaw/installer
```
3：安装依赖
```
go mod tidy
```
4：编译
```
go build -o installer.exe .
```
