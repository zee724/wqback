#!/usr/bin/env bash
set -Eeuo pipefail

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[INFO]${NC} $*"; }
ok(){ echo -e "${GREEN}[OK]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
die(){ echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "请用 root 运行：sudo bash $0"

. /etc/os-release
case "${ID:-}" in
  ubuntu|debian) ;;
  *) die "仅支持 Debian/Ubuntu。" ;;
esac

case "$(uname -m)" in
  x86_64|amd64) SB_ARCH="amd64" ;;
  aarch64|arm64) SB_ARCH="arm64" ;;
  *) die "仅支持 amd64 / arm64。" ;;
esac

ACME="/root/.acme.sh/acme.sh"
CONF_DIR="/etc/sing-box"
CERT_DIR="$CONF_DIR/cert"
CONF_FILE="$CONF_DIR/config.json"
SERVICE_FILE="/etc/systemd/system/sing-box.service"

repair_apt_if_needed() {
  info "检查 APT/DPKG…"
  dpkg --configure -a >/dev/null 2>&1 || true

  if [[ "$(uname -r)" != "4.11.8-041108-generic" ]]; then
    for pkg in linux-headers-4.11.8-041108-generic linux-headers-4.11.8-041108; do
      if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -qE 'install ok (installed|unpacked|half-configured)'; then
        warn "清理旧内核头文件 $pkg"
        dpkg --purge --force-all "$pkg" >/dev/null 2>&1 || true
      fi
    done
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt-get -f install -y || die "APT 依赖仍损坏，请先手工修复 apt。"
  apt-get update -y
  apt-get install -y ca-certificates curl tar openssl socat
}

check_domain() {
  local domain="$1"
  local public_ip dns_ip
  public_ip="$(curl -4 -fsS https://ipv4.icanhazip.com | tr -d '\r\n' || true)"
  dns_ip="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | head -n1 || true)"
  info "VPS IPv4：${public_ip:-无法检测}"
  info "域名 A 记录：${dns_ip:-无法解析}"
  [[ -n "$dns_ip" ]] || die "域名没有可用 A 记录。"
  if [[ -n "$public_ip" && "$dns_ip" != "$public_ip" ]]; then
    warn "域名 A 记录与 VPS IPv4 不一致。"
    read -r -p "仍继续？[y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]] || exit 1
  fi
  if getent ahostsv6 "$domain" >/dev/null 2>&1; then
    warn "检测到 IPv6/AAAA 解析；若 VPS IPv6 不通，请删除 AAAA。"
  fi
}

check_ports() {
  systemctl stop sing-box >/dev/null 2>&1 || true
  systemctl stop trojan >/dev/null 2>&1 || true
  if command -v ss >/dev/null 2>&1; then
    if ss -lntp 2>/dev/null | grep -qE '[:.]443[[:space:]]'; then
      ss -lntp | grep ':443' || true
      die "443 端口被占用。"
    fi
    if ss -lntp 2>/dev/null | grep -qE '[:.]80[[:space:]]'; then
      if systemctl is-active --quiet nginx 2>/dev/null; then
        warn "临时停止 nginx 以申请证书。"
        systemctl stop nginx || true
        sleep 1
      fi
      if ss -lntp 2>/dev/null | grep -qE '[:.]80[[:space:]]'; then
        ss -lntp | grep ':80' || true
        die "80 端口仍被占用。"
      fi
    fi
  fi
}

install_singbox() {
  info "获取 sing-box 最新稳定版…"
  local api version url tmp bin
  api="$(curl -4 -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest)"
  version="$(printf '%s' "$api" | sed -n 's/.*"tag_name":[[:space:]]*"v\([^"]*\)".*/\1/p' | head -n1)"
  [[ -n "$version" ]] || die "无法获取 sing-box 最新版本。"
  url="https://github.com/SagerNet/sing-box/releases/download/v${version}/sing-box-${version}-linux-${SB_ARCH}.tar.gz"
  tmp="$(mktemp -d)"
  curl -4 -fL --retry 3 "$url" -o "$tmp/sing-box.tar.gz"
  tar -xzf "$tmp/sing-box.tar.gz" -C "$tmp"
  bin="$(find "$tmp" -type f -name sing-box | head -n1)"
  [[ -n "$bin" ]] || die "解压后未找到 sing-box。"
  install -m 0755 "$bin" /usr/local/bin/sing-box
  rm -rf "$tmp"
  /usr/local/bin/sing-box version
}

install_acme() {
  if [[ ! -x "$ACME" ]]; then
    info "安装 acme.sh…"
    curl -4 -fsSL https://get.acme.sh | sh
  fi
  "$ACME" --set-default-ca --server letsencrypt >/dev/null
  "$ACME" --upgrade --auto-upgrade >/dev/null 2>&1 || true
}

issue_cert() {
  local domain="$1"
  mkdir -p "$CERT_DIR"
  chmod 700 "$CERT_DIR"
  info "申请 Let's Encrypt ECC 证书…"
  "$ACME" --issue --server letsencrypt --listen-v4 --keylength ec-256 --standalone -d "$domain" || true
  "$ACME" --install-cert --ecc -d "$domain" \
    --key-file "$CERT_DIR/private.key" \
    --fullchain-file "$CERT_DIR/fullchain.pem" \
    --reloadcmd "systemctl is-enabled sing-box >/dev/null 2>&1 && systemctl restart sing-box || true"
  [[ -s "$CERT_DIR/private.key" ]] || die "私钥安装失败。"
  [[ -s "$CERT_DIR/fullchain.pem" ]] || die "证书安装失败。"
  chmod 600 "$CERT_DIR/private.key"
  chmod 644 "$CERT_DIR/fullchain.pem"
  openssl x509 -in "$CERT_DIR/fullchain.pem" -noout -subject -dates
}

write_config() {
  local domain="$1" password="$2"
  mkdir -p "$CONF_DIR"
  cat > "$CONF_FILE" <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "0.0.0.0",
      "listen_port": 443,
      "users": [
        {
          "name": "shadowrocket",
          "password": "$password"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$domain",
        "certificate_path": "$CERT_DIR/fullchain.pem",
        "key_path": "$CERT_DIR/private.key"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF
  /usr/local/bin/sing-box check -c "$CONF_FILE"
}

write_service() {
  cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=sing-box Trojan Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable sing-box >/dev/null
  systemctl restart sing-box
  sleep 2
  if ! systemctl is-active --quiet sing-box; then
    systemctl status sing-box --no-pager -l || true
    journalctl -u sing-box -n 80 --no-pager || true
    die "sing-box 启动失败。"
  fi
}

open_firewall() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow 80/tcp >/dev/null || true
    ufw allow 443/tcp >/dev/null || true
  fi
}

install_all() {
  echo "Modern Trojan Installer (sing-box)"
  read -r -p "请输入绑定本 VPS 的域名: " DOMAIN
  [[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || die "域名格式不正确。"

  read -r -s -p "请输入 Trojan 密码（留空自动生成）: " PASSWORD
  echo
  [[ -n "$PASSWORD" ]] || PASSWORD="$(openssl rand -hex 16)"
  if [[ "$PASSWORD" == *'"'* || "$PASSWORD" == *'\'* ]]; then
    die "密码不要包含双引号或反斜杠。"
  fi

  repair_apt_if_needed
  check_domain "$DOMAIN"
  open_firewall
  check_ports
  install_singbox
  install_acme
  issue_cert "$DOMAIN"
  write_config "$DOMAIN" "$PASSWORD"
  write_service

  echo
  echo "================ 安装成功 ================"
  echo "Shadowrocket："
  echo "类型：Trojan"
  echo "地址：$DOMAIN"
  echo "端口：443"
  echo "密码：$PASSWORD"
  echo "TLS：开启"
  echo "SNI：$DOMAIN"
  echo "跳过证书验证：关闭"
  echo
  echo "检查命令："
  echo "systemctl status sing-box --no-pager -l"
  echo "journalctl -u sing-box -n 100 --no-pager"
  echo "ss -lntp | grep ':443'"
}

status_all() {
  systemctl status sing-box --no-pager -l || true
  echo
  ss -lntp 2>/dev/null | grep ':443' || true
  echo
  journalctl -u sing-box -n 80 --no-pager || true
}

uninstall_all() {
  warn "将删除 sing-box 服务和 /etc/sing-box 配置，不删除 acme.sh。"
  read -r -p "确认卸载？[y/N]: " ans
  [[ "$ans" =~ ^[Yy]$ ]] || exit 0
  systemctl stop sing-box >/dev/null 2>&1 || true
  systemctl disable sing-box >/dev/null 2>&1 || true
  rm -f "$SERVICE_FILE" /usr/local/bin/sing-box
  rm -rf "$CONF_DIR"
  systemctl daemon-reload
  ok "已卸载。"
}

echo "1) 安装/重装"
echo "2) 查看状态"
echo "3) 卸载"
echo "0) 退出"
read -r -p "请选择: " CHOICE
case "$CHOICE" in
  1) install_all ;;
  2) status_all ;;
  3) uninstall_all ;;
  0) exit 0 ;;
  *) die "无效选择。" ;;
esac
