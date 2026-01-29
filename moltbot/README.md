## Moltbot (原 ClawdBot) 一键安装与管理脚本

### linux 脚本
```
bash <(curl -sSL https://raw.githubusercontent.com/sky22333/shell/main/moltbot/install.sh)
```

### windows 脚本
直接下载使用编译好的二进制文件：https://github.com/sky22333/shell/raw/main/moltbot/installer/installer.exe

下载后使用管理员权限运行

支持环境变量配置代理域名(已默认内置此代理)
```
set GIT_PROXY=https://g.blfrp.cn/

installer.exe
```

如果你选择跳过设置TG机器人，启动后可以访问ClawdBot内置的Web面板进行对话：`http://127.0.0.1:18789`

### 构建（可选）
如果你不放心预编译的二进制文件，可以自己构建。

1：windows 安装go环境：https://golang.org/doc/install

2：进入项目目录
```
cd moltbot/installer
```
3：安装依赖
```
go mod tidy
```
4：编译
```
go build -o installer.exe .
```
