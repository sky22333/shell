#!/usr/bin/env bash
# realm 管理脚本 — 纯转发 / TLS / WSS
# 用法: sudo ./realm-manager.sh [install|uninstall|restart|logs]
set -euo pipefail

# 颜色定义
if [[ -t 1 ]]; then
  R=$'\033[31m' G=$'\033[32m' Y=$'\033[33m' C=$'\033[36m' B=$'\033[1m' D=$'\033[2m' N=$'\033[0m'
else
  R= G= Y= C= B= D= N=
fi

# 路径与默认值
readonly REALM_BIN="/usr/local/bin/realm"
readonly REALM_DIR="/etc/realm"
readonly CONF="${REALM_DIR}/config.toml"
readonly RULES="${REALM_DIR}/rules.lst"
readonly UNIT="/etc/systemd/system/realm.service"
readonly DOWNLOAD_BASE="https://github.com/zhboner/realm/releases/latest/download"
readonly SERVICE_NAME="realm"

readonly DEFAULT_SNI="bong.com"
readonly DEFAULT_WSS_HOST="cdn.example.com"
readonly DEFAULT_WSS_PATH="/ws"

# 规则: id|type|listen|remote|sni|host|path|note

# 工具
die()  { echo -e "${R}错误:${N} $*" >&2; exit 1; }
info() { echo -e "${G}>>${N} $*"; }
hint() { echo -e "${Y}>>${N} $*"; }
need_root() { [[ ${EUID:-} -eq 0 ]] || die "请用 root 运行"; }

ask() {
  local prompt="$1" default="${2:-}" value
  if [[ -n "$default" ]]; then
    read -rp "$(echo -e "${C}${prompt}${N} ${D}[${default}]${N}: ")" value
  else
    read -rp "$(echo -e "${C}${prompt}${N}: ")" value
  fi
  echo "${value:-$default}"
}

confirm() {
  local prompt="${1:-确认?}"
  local answer
  read -rp "$(echo -e "${Y}${prompt}${N} [y/N]: ")" answer
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

# 状态
is_installed() {
  [[ -x "$REALM_BIN" || -f "$UNIT" || -d "$REALM_DIR" ]]
}

version_line() {
  if [[ -x "$REALM_BIN" ]]; then
    "$REALM_BIN" -v 2>/dev/null | head -1 || echo "realm"
  else
    echo "未安装"
  fi
}

show_install_info() {
  [[ -x "$REALM_BIN" ]] && info "二进制: $(version_line)"
  [[ -f "$UNIT" ]]       && info "服务:   ${SERVICE_NAME}.service"
  [[ -d "$REALM_DIR" ]]  && info "配置:   ${REALM_DIR}"
}

# 下载
arch_package() {
  case "$(uname -m)" in
    x86_64|amd64)  echo "realm-x86_64-unknown-linux-musl.tar.gz" ;;
    aarch64|arm64) echo "realm-aarch64-unknown-linux-musl.tar.gz" ;;
    armv7l|armv6l) echo "realm-armv7-unknown-linux-musleabihf.tar.gz" ;;
    *) die "不支持的架构: $(uname -m)" ;;
  esac
}

download_realm_binary() {
  local package temp_dir
  package="$(arch_package)"
  temp_dir="$(mktemp -d)"

  info "下载 latest: ${package}"
  curl -fsSL "${DOWNLOAD_BASE}/${package}" -o "${temp_dir}/${package}"
  tar -xzf "${temp_dir}/${package}" -C "$temp_dir"
  install -m755 "${temp_dir}/realm" "$REALM_BIN"
  rm -rf "$temp_dir"
}

# systemd
write_systemd_unit() {
  cat >"$UNIT" <<EOF
[Unit]
Description=Realm Port Forward
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=120
StartLimitBurst=5

[Service]
Type=simple
ExecStart=${REALM_BIN} -c ${CONF}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

svc_reload()   { systemctl daemon-reload; }
svc_enable()   { systemctl enable "$SERVICE_NAME"; }
svc_start() {
  if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl restart "$SERVICE_NAME"
  else
    systemctl start "$SERVICE_NAME"
  fi
}
svc_stop()     { systemctl stop "$SERVICE_NAME" 2>/dev/null || true; systemctl reset-failed "$SERVICE_NAME" 2>/dev/null || true; }
svc_stop_all() {
  svc_stop
  systemctl disable "$SERVICE_NAME" 2>/dev/null || true
}

has_rules() {
  [[ -f "$RULES" ]] || return 1
  local id
  while IFS='|' read -r id _; do
    [[ -n "${id:-}" ]] && return 0
  done <"$RULES"
  return 1
}

svc_apply() {
  if has_rules; then
    if svc_start; then
      return 0
    fi
    hint "服务启动失败，请查看: journalctl -u ${SERVICE_NAME} -n 20 --no-pager"
    return 1
  fi
  svc_stop
}

# 安装 / 卸载 / 重启
install_realm() {
  need_root

  if is_installed; then
    info "检测到已安装:"
    show_install_info
    echo -e "  ${D}1${N}: 取消  ${D}2${N}: 覆盖重装 (保留规则)  ${D}3${N}: 覆盖重装 (清空配置)"
    case "$(ask "选择" "1")" in
      1) info "已取消"; return ;;
      3) rm -rf "$REALM_DIR" ;;
    esac
  fi

  download_realm_binary
  mkdir -p "$REALM_DIR"
  touch "$RULES"
  write_systemd_unit
  render_config
  svc_reload && svc_enable && svc_apply

  info "安装完成"
  show_install_info
  has_rules || hint "尚未添加规则，服务未启动，请添加规则后自动运行"
}

uninstall_realm() {
  need_root
  is_installed || { hint "未安装，无需卸载"; return; }

  confirm "确认卸载 (含全部配置)?" || return 0

  svc_stop_all
  rm -f "$UNIT" "$REALM_BIN"
  rm -rf "$REALM_DIR"
  svc_reload

  info "已卸载"
}

restart_realm() {
  need_root
  render_config
  if has_rules; then
    svc_start && info "已重启" || hint "启动失败，请查看日志 (菜单 9)"
  else
    svc_stop
    hint "无规则，服务已停止"
  fi
}

# 规则读写
rules_init() { mkdir -p "$REALM_DIR"; touch "$RULES"; }

next_rule_id() {
  local max=0 current
  [[ -f "$RULES" ]] || { echo 1; return; }
  while IFS='|' read -r current _; do
    [[ "$current" =~ ^[0-9]+$ && "$current" -gt "$max" ]] && max="$current"
  done <"$RULES"
  echo $((max + 1))
}

assert_listen_free() {
  local listen="$1" id existing_listen
  while IFS='|' read -r id _ existing_listen _; do
    [[ "$existing_listen" == "$listen" ]] && die "监听 ${listen} 已被规则 #${id} 占用"
  done <"${RULES:-/dev/null}" 2>/dev/null || true
}

save_rule() {
  # 固定 8 字段: id|type|listen|remote|sni|host|path|note
  printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
    "$1" "$2" "$3" "$4" "${5:-}" "${6:-}" "${7:-}" "${8:-}" >>"$RULES"
}

apply_rules() {
  render_config
  svc_apply || true
}

# 生成 config.toml
render_endpoint_block() {
  local id="$1" type="$2" listen="$3" remote="$4"
  local sni="$5" host="$6" path="$7" note="$8"

  cat >>"$CONF" <<EOF

# [${id}] ${note:-}
[[endpoints]]
listen = "${listen}"
remote = "${remote}"
EOF

  case "$type" in
    forward)
      cat >>"$CONF" <<EOF
network = { no_tcp = false, use_udp = true }
EOF
      ;;
    tls_in)
      cat >>"$CONF" <<EOF
remote_transport = "tls;sni=${sni};insecure"
EOF
      ;;
    tls_out)
      cat >>"$CONF" <<EOF
listen_transport = "tls;servername=${sni}"
EOF
      ;;
    wss_in)
      cat >>"$CONF" <<EOF
remote_transport = "ws;host=${host};path=${path};tls;sni=${sni};insecure"
EOF
      ;;
    wss_out)
      cat >>"$CONF" <<EOF
listen_transport = "ws;host=${host};path=${path};tls;servername=${sni}"
EOF
      ;;
    *)
      die "未知规则类型: ${type} (#${id})"
      ;;
  esac
}

render_config() {
  need_root
  mkdir -p "$REALM_DIR"

  cat >"$CONF" <<'EOF'
[log]
level = "warn"
output = "stdout"
EOF

  [[ -f "$RULES" ]] || { echo "endpoints = []" >>"$CONF"; return 0; }

  local id type listen remote sni host path note count=0
  while IFS='|' read -r id type listen remote sni host path note; do
    [[ -n "${id:-}" ]] || continue
    render_endpoint_block "$id" "$type" "$listen" "$remote" \
      "$sni" "$host" "$path" "$note"
    count=$((count + 1))
  done <"$RULES"

  if (( count == 0 )); then
    echo "endpoints = []" >>"$CONF"
  fi
}

# 添加规则
pick_tunnel_role() {
  echo -e "  ${D}1${N}: 入口  ${D}2${N}: 出口" >&2
  ask "角色"
}

add_rule_forward() {
  local id="$1" note="$2" listen remote

  listen=$(ask "监听 (例 0.0.0.0:8899)")
  assert_listen_free "$listen"
  remote=$(ask "目标 (例 落地IP:9900)")

  save_rule "$id" forward "$listen" "$remote" "" "" "" "$note"
}

add_rule_tls() {
  local id="$1" note="$2" role listen remote sni

  sni=$(ask "SNI" "$DEFAULT_SNI")
  role="$(pick_tunnel_role)"

  case "$role" in
    1)
      listen=$(ask "监听")
      assert_listen_free "$listen"
      remote=$(ask "出口 IP:TLS端口")
      save_rule "$id" tls_in  "$listen" "$remote" "$sni" "" "" "$note"
      hint "出口机添加 TLS 出口，SNI=${sni}，端口与 remote 一致"
      ;;
    2)
      listen=$(ask "TLS 监听 (例 0.0.0.0:8443)")
      assert_listen_free "$listen"
      remote=$(ask "本地目标 (例 127.0.0.1:9900)")
      save_rule "$id" tls_out "$listen" "$remote" "$sni" "" "" "$note"
      ;;
    *) die "无效角色" ;;
  esac
}

add_rule_wss() {
  local id="$1" note="$2" role listen remote sni host path

  sni=$(ask "SNI" "$DEFAULT_SNI")
  host=$(ask "Host" "$DEFAULT_WSS_HOST")
  path=$(ask "Path" "$DEFAULT_WSS_PATH")
  role="$(pick_tunnel_role)"

  case "$role" in
    1)
      listen=$(ask "监听")
      assert_listen_free "$listen"
      remote=$(ask "出口 IP:端口")
      save_rule "$id" wss_in  "$listen" "$remote" "$sni" "$host" "$path" "$note"
      hint "出口机添加 WSS 出口，host/path/sni 保持一致"
      ;;
    2)
      listen=$(ask "WSS 监听")
      assert_listen_free "$listen"
      remote=$(ask "本地目标")
      save_rule "$id" wss_out "$listen" "$remote" "$sni" "$host" "$path" "$note"
      ;;
    *) die "无效角色" ;;
  esac
}

add_rule() {
  need_root
  rules_init

  echo -e "  ${D}1${N}: 纯转发  ${D}2${N}: TLS  ${D}3${N}: WSS"
  local mode id note
  mode="$(ask "模式")"
  id="$(next_rule_id)"
  note="$(ask "备注" "")"

  case "$mode" in
    1) add_rule_forward "$id" "$note" ;;
    2) add_rule_tls   "$id" "$note" ;;
    3) add_rule_wss   "$id" "$note" ;;
    *) die "无效模式" ;;
  esac

  apply_rules
  info "规则 #${id} 已添加"
}

del_rule() {
  need_root
  has_rules || die "无规则"

  list_rules
  echo
  local rid
  rid="$(ask "删除 ID")"
  [[ "$rid" =~ ^[0-9]+$ ]] || die "无效 ID"
  grep -q "^${rid}|" "$RULES" || die "规则 #${rid} 不存在"

  awk -F'|' -v id="$rid" '$1 != id' "$RULES" >"${RULES}.tmp"
  mv "${RULES}.tmp" "$RULES"
  apply_rules
  info "规则 #${rid} 已删除"
  has_rules || hint "已无规则，服务已停止"
}

list_rules() {
  if [[ ! -f "$RULES" ]] || ! has_rules; then
    echo -e "${D}(无规则)${N}"
    return
  fi
  [[ -r "$RULES" ]] || { hint "无法读取规则 (需 root)"; return; }

  printf "${B}${C}%-4s %-8s %-20s %-20s %s${N}\n" "ID" "类型" "监听" "目标" "备注"

  local id type listen remote sni host path note
  while IFS='|' read -r id type listen remote sni host path note; do
    [[ -n "${id:-}" ]] || continue
    printf "${G}%-4s${N} ${C}%-8s${N} %-20s %-20s ${D}%s${N}\n" \
      "$id" "$type" "$listen" "$remote" "$note"
  done <"$RULES"
}

show_config() {
  if [[ -f "$CONF" ]]; then
    echo -e "${C}# ${CONF}${N}"
    cat "$CONF" 2>/dev/null || hint "无法读取配置 (需 root)"
  else
    echo -e "${D}(无配置)${N}"
  fi
}

show_status() {
  systemctl status "$SERVICE_NAME" --no-pager 2>/dev/null || hint "服务未运行"
}

view_logs() {
  [[ -f "$UNIT" ]] || { hint "服务未配置"; return 0; }
  hint "实时日志 (Ctrl+C 返回菜单)"
  journalctl -u "$SERVICE_NAME" -n 50 -f --no-pager || {
    local rc=$?
    [[ $rc -eq 130 ]] && return 0
    die "无法读取日志"
  }
}

# 菜单
print_menu() {
  local status
  echo
  echo -e "${B}${C}realm 管理${N}"
  if is_installed; then
    status="${G}$(version_line)${N}"
  else
    status="${Y}未安装${N}"
  fi
  echo -e " 状态: ${status}"
  echo
  echo -e " ${D}1${N}: 安装"
  echo -e " ${D}2${N}: 卸载"
  echo -e " ${D}3${N}: 添加规则"
  echo -e " ${D}4${N}: 删除规则"
  echo -e " ${D}5${N}: 查看规则"
  echo -e " ${D}6${N}: 查看配置"
  echo -e " ${D}7${N}: 重启"
  echo -e " ${D}8${N}: 状态"
  echo -e " ${D}9${N}: 实时日志"
  echo -e " ${D}0${N}: 退出"
}

run_menu() {
  local choice
  while true; do
    print_menu
    choice="$(ask "选择")"
    case "$choice" in
      1) install_realm ;;
      2) uninstall_realm ;;
      3) add_rule ;;
      4) del_rule ;;
      5) list_rules ;;
      6) show_config ;;
      7) restart_realm ;;
      8) show_status ;;
      9) view_logs ;;
      0) exit 0 ;;
      *) hint "无效选项" ;;
    esac
  done
}

# 入口
main() {
  case "${1:-}" in
    install)   install_realm ;;
    uninstall) uninstall_realm ;;
    restart)   restart_realm ;;
    logs)      view_logs ;;
    "")        run_menu ;;
    *) die "用法: $0 [install|uninstall|restart|logs]" ;;
  esac
}

main "$@"
