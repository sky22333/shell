#!/bin/bash

PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-i18n-base-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-i18n-homeproxy-zh-cn"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn"

# Docker需要1G以上空间，下载汉化包即可自动安装对应软件和依赖
# PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"

make image PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE="512"

# 通常需要传入路由器型号，例如：PROFILE=friendlyarm_nanopi-r2s
# 路由器型号id查询地址：https://downloads.immortalwrt.org/releases/24.10.4/.overview.json
