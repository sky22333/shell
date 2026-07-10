#!/usr/bin/env bash

# Xray 安装脚本（极简版）
# 固定版本 v1.8.4
# 支持通过 -p 参数设置 GitHub 加速前缀（如 https://gh-proxy.com/）
# 仅适用于 Linux 系统，需 root 权限

XRAY_VERSION="v1.8.4"
XRAY_BIN_URL="github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip"
INSTALL_PATH="/usr/local/bin/xray"
SERVICE_PATH="/etc/systemd/system/xray.service"
CONFIG_PATH="/usr/local/etc/xray/config.json"

# github文件加速前缀
GH_PROXY="https://gh-proxy.com"

show_help() {
  echo "用法: $0 [-p <gh-proxy前缀>] [-u|--uninstall]"
  echo "  -p    （可选）GitHub 文件加速前缀，如 https://gh-proxy.com"
  echo "  -u, --uninstall  卸载 Xray 及所有相关文件和服务"
  echo "此脚本会自动下载安装 Xray ${XRAY_VERSION}，并注册 systemd 服务。"
  exit 0
}

# 检查 root 权限
if [[ "$(id -u)" -ne 0 ]]; then
  echo "请以 root 用户运行此脚本。"
  exit 1
fi

# 解析参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p)
      shift
      GH_PROXY="$1"
      ;;
    -u|--uninstall)
      echo "正在卸载 Xray ..."
      systemctl stop xray 2>/dev/null
      systemctl disable xray 2>/dev/null
      rm -f /usr/local/bin/xray
      rm -rf /usr/local/etc/xray
      rm -f /etc/systemd/system/xray.service
      rm -rf /var/log/xray
      systemctl daemon-reload
      echo "Xray 及相关文件已卸载。"
      exit 0
      ;;
    -h|--help)
      show_help
      ;;
    *)
      show_help
      ;;
  esac
  shift
done

# 自动安装依赖（curl 和 unzip）
install_pkg() {
  PKG_NAME="$1"
  if command -v apt >/dev/null 2>&1; then
    apt update && apt install -y "$PKG_NAME"
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y "$PKG_NAME"
  elif command -v yum >/dev/null 2>&1; then
    yum install -y "$PKG_NAME"
  elif command -v zypper >/dev/null 2>&1; then
    zypper install -y "$PKG_NAME"
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm "$PKG_NAME"
  elif command -v emerge >/dev/null 2>&1; then
    emerge -qv "$PKG_NAME"
  else
    echo "未检测到支持的包管理器，请手动安装 $PKG_NAME 后重试。"
    exit 1
  fi
}

for cmd in curl unzip; do
  if ! command -v $cmd >/dev/null 2>&1; then
    echo "缺少依赖: $cmd，正在尝试自动安装..."
    install_pkg "$cmd"
    if ! command -v $cmd >/dev/null 2>&1; then
      echo "$cmd 安装失败，请手动安装后重试。"
      exit 1
    fi
  fi
done

TMP_DIR="$(mktemp -d)"
ZIP_FILE="$TMP_DIR/xray.zip"

# 拼接加速前缀
if [[ -n "$GH_PROXY" ]]; then
  DOWNLOAD_URL="${GH_PROXY%/}/$XRAY_BIN_URL"
else
  DOWNLOAD_URL="https://$XRAY_BIN_URL"
fi

echo "下载 Xray: $DOWNLOAD_URL"
curl -L -o "$ZIP_FILE" "$DOWNLOAD_URL"
if [[ $? -ne 0 ]]; then
  echo "下载失败，请检查网络或加速前缀。"
  rm -rf "$TMP_DIR"
  exit 1
fi

unzip -q "$ZIP_FILE" -d "$TMP_DIR"
if [[ $? -ne 0 ]]; then
  echo "解压失败。"
  rm -rf "$TMP_DIR"
  exit 1
fi

install -m 755 "$TMP_DIR/xray" "$INSTALL_PATH"

# 生成 systemd 服务文件（与原脚本一致，自动适配 User 和权限）
INSTALL_USER="root"
if [[ -f '/usr/local/bin/xray' ]]; then
  # 若已存在旧服务文件，尝试读取 User 字段
  OLD_USER=$(grep '^[ \t]*User[ \t]*=' /etc/systemd/system/xray.service 2>/dev/null | tail -n 1 | awk -F = '{print $2}' | awk '{print $1}')
  if [[ -n "$OLD_USER" ]]; then
    INSTALL_USER="$OLD_USER"
  fi
fi
if ! id "$INSTALL_USER" >/dev/null 2>&1; then
  INSTALL_USER="root"
fi
INSTALL_USER_UID=$(id -u "$INSTALL_USER")

# 权限相关字段
temp_CapabilityBoundingSet="CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE"
temp_AmbientCapabilities="AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE"
temp_NoNewPrivileges="NoNewPrivileges=true"
if [[ "$INSTALL_USER_UID" -eq 0 ]]; then
  temp_CapabilityBoundingSet="#${temp_CapabilityBoundingSet}"
  temp_AmbientCapabilities="#${temp_AmbientCapabilities}"
  temp_NoNewPrivileges="#${temp_NoNewPrivileges}"
fi

cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=$INSTALL_USER
${temp_CapabilityBoundingSet}
${temp_AmbientCapabilities}
${temp_NoNewPrivileges}
ExecStart=$INSTALL_PATH run -config $CONFIG_PATH
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "$SERVICE_PATH"
systemctl daemon-reload

# 生成最简配置文件
mkdir -p "$(dirname $CONFIG_PATH)"
echo '{}' > "$CONFIG_PATH"

# 启动并设置开机自启
systemctl enable xray
systemctl restart xray
sleep 1
if systemctl is-active --quiet xray; then
  echo "Xray ${XRAY_VERSION} 安装并启动成功。"
else
  echo "Xray 启动失败，请检查日志。"
fi

# 清理临时文件
rm -rf "$TMP_DIR"
