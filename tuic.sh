#!/bin/bash
set -euo pipefail
export LC_ALL=C
IFS=$'\n\t'

MASQ_DOMAIN="www.bing.com"   # 用作证书 CN
SERVER_TOML="server.toml"
CERT_PEM="tuic-cert.pem"
KEY_PEM="tuic-key.pem"
LINK_TXT="tuic_link.txt"
TUIC_BIN="./tuic-server"

random_port() { echo $(( (RANDOM % 40000) + 20000 )); }

read_port() {
  if [[ $# -ge 1 && -n "${1:-}" ]]; then
    TUIC_PORT="$1"; return
  fi
  TUIC_PORT=$(random_port)
}

load_existing() {
  if [[ -f "$SERVER_TOML" ]]; then
    TUIC_PORT=$(grep "bind" server.toml | grep -Eo '[0-9]+')
    TUIC_UUID=$(grep "uuid" server.toml | awk '{print $3}' | tr -d '"')
    TUIC_PASSWORD=$(grep "password" server.toml | awk '{print $3}' | tr -d '"')
    return 0
  fi
  return 1
}

generate_cert() {
  if [[ -f "$CERT_PEM" && -f "$KEY_PEM" ]]; then return; fi
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "$KEY_PEM" -out "$CERT_PEM" \
    -subj "/CN=${MASQ_DOMAIN}" -days 365 -nodes >/dev/null 2>&1
  chmod 600 "$KEY_PEM"
  chmod 644 "$CERT_PEM"
}

check_tuic() {
  if [[ -x "$TUIC_BIN" ]]; then return; fi
  curl -L -o "$TUIC_BIN" "https://github.com/EAimTY/tuic/releases/download/v5.0.0/tuic-server-x86_64-linux"
  chmod +x "$TUIC_BIN"
}

# TUIC v5 配置格式
generate_config() {
cat > "$SERVER_TOML" <<EOF
log_level = "warn"

[server]
bind = "0.0.0.0:${TUIC_PORT}"
certificate = "${CERT_PEM}"
private_key = "${KEY_PEM}"

[server.quic]
disable_path_mtu_discovery = false

[[users]]
uuid = "${TUIC_UUID}"
password = "${TUIC_PASSWORD}"
EOF
}

get_ip() {
  curl -s https://api64.ipify.org || echo "127.0.0.1"
}

# TUIC v5 链接：参数完全变化
generate_link() {
  local ip="$1"
  cat > "$LINK_TXT" <<EOF
tuic5://${TUIC_UUID}:${TUIC_PASSWORD}@${ip}:${TUIC_PORT}?sni=${MASQ_DOMAIN}&alpn=h3&insecure=1#TUIC5-${ip}
EOF
  cat "$LINK_TXT"
}

run_forever() {
  while true; do
    "$TUIC_BIN" -c "$SERVER_TOML" >/dev/null 2>&1 || true
    sleep 5
  done
}

main() {
  if ! load_existing "$@"; then
    read_port "$@"
    TUIC_UUID="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen)"
    TUIC_PASSWORD="$(openssl rand -hex 16)"
    generate_cert
    check_tuic
    generate_config
  else
    generate_cert
    check_tuic
  fi

  ip="$(get_ip)"
  generate_link "$ip"
  run_forever
}

main "$@"
