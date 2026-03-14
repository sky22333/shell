## openclaw (原 ClawdBot) 一键安装与管理脚本

### linux 脚本
```
bash <(curl -sSL https://raw.githubusercontent.com/sky22333/shell/main/openclaw/install.sh)
```

### mac 脚本
```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/sky22333/shell/main/openclaw/install_mac.sh)"
```

### windows 脚本
直接下载使用编译好的二进制文件：https://github.com/sky22333/shell/raw/main/openclaw/installer/installer.exe

CMD修改加速域名环境变量（可选）
```
set GIT_PROXY=https://hub.cmoko.com/
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

---

相关文档：https://clawd.org.cn/reference/cli-cheatsheet



### win系统Tui预览

![](https://img.erpweb.eu.org/imgs/2026/03/ffacc5e6f456ebf7.png)