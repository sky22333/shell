#!/bin/bash

mkdir -p bin
chmod -R 777 bin
chmod +x build.sh
chmod +x files/etc/uci-defaults/99-custom.sh

docker run --rm -it \
-v ./bin:/home/build/immortalwrt/bin \
-v ./files/etc/uci-defaults:/home/build/immortalwrt/files/etc/uci-defaults \
-v ./build.sh:/home/build/immortalwrt/build.sh \
immortalwrt/imagebuilder:x86-64-openwrt-24.10.4 /home/build/immortalwrt/build.sh