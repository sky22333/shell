## Moltbot (原 ClawdBot) 一键安装与管理脚本

### linux 脚本
```
bash <(curl -sSL https://raw.githubusercontent.com/sky22333/shell/main/moltbot/install.sh)
```

### windows 安装脚本
下载并运行安装程序：https://github.com/sky22333/shell/blob/main/moltbot/installer/installer.exe

Web面板：
```
http://127.0.0.1:18789
```

### 构建
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