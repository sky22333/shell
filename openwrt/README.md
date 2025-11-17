### immortalwrt的docker构建脚本

根据自己情况修改，修改后执行`docker-run.sh`脚本即可自动构建，构建出来的固件在当前的`bin`目录。

- 初始化脚本修改：`files/etc/uci-defaults/99-custom.sh`

- 内置软件包修改：`build.sh`

- 镜像版本修改：`docker-run.sh`，选择符合自己设备的系统架构。