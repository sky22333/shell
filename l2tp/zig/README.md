# l2tp

## 编译

Windows:

```powershell
zig build-exe .\l2tp.zig -target x86_64-linux-gnu -O ReleaseSmall -fstrip -femit-bin=l2tp
```

Linux:

```bash
zig build-exe ./l2tp.zig -target x86_64-linux-gnu -O ReleaseSmall -fstrip -femit-bin=l2tp
```

编译只需要安装 Zig。

## 使用

```bash
chmod +x l2tp
sudo ./l2tp
sudo ./l2tp -out
sudo ./l2tp -rm
```

`-out`：安装后配置透明代理分流。

`-rm`：卸载服务并清理分流规则。
