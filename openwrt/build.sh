#!/bin/bash

PACKAGES=""
PACKAGES="$PACKAGES curl"
PACKAGES="$PACKAGES luci-i18n-base-zh-cn"
PACKAGES="$PACKAGES luci-i18n-firewall-zh-cn"
PACKAGES="$PACKAGES luci-i18n-package-manager-zh-cn"
PACKAGES="$PACKAGES luci-theme-argon"
PACKAGES="$PACKAGES luci-app-homeproxy"
PACKAGES="$PACKAGES luci-i18n-homeproxy-zh-cn"
PACKAGES="$PACKAGES luci-app-ttyd"
PACKAGES="$PACKAGES luci-i18n-ttyd-zh-cn"
PACKAGES="$PACKAGES luci-app-diskman"
PACKAGES="$PACKAGES luci-i18n-diskman-zh-cn"
PACKAGES="$PACKAGES luci-app-filemanager"
PACKAGES="$PACKAGES luci-i18n-filemanager-zh-cn"

# docker(需要1G以上空间)
# PACKAGES="$PACKAGES luci-app-dockerman"
# PACKAGES="$PACKAGES luci-i18n-dockerman-zh-cn"

make image PACKAGES="$PACKAGES" FILES="/home/build/immortalwrt/files" ROOTFS_PARTSIZE="512"

# 通常需要传入路由器型号，例如：PROFILE=nanopi-r2s
