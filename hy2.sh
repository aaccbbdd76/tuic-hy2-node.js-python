#!/usr/bin/env bash
set -e

HYSTERIA_VERSION="v2.6.5"
DEFAULT_PORT=22222
AUTH_PASSWORD="ieshare2025"
CERT_FILE="cert.pem"
KEY_FILE="key.pem"
SNI="www.bing.com"
ALPN="h3"

# 端口
if [ $# -ge 1 ]; then
    SERVER_PORT="$1"
else
    SERVER_PORT="$DEFAULT_PORT"
fi

# 架构
m=$(uname -m | tr A-Z a-z)
case "$m" in
  *aarch64*|*arm64*) ARCH=arm64;;
  *x86_64*|*amd64*)  ARCH=amd64;;
  *) echo "arch error"; exit 1;;
esac

BIN_NAME="hysteria-linux-${ARCH}"
BIN_PATH="./${BIN_NAME}"

# 下载（减少 curl 参数；减少重试逻辑）
[ -f "$BIN_PATH" ] || {
  curl -fsSL -o "$BIN_PATH" \
  "https://github.com/apernet/hysteria/releases/download/app/${HYSTERIA_VERSION}/${BIN_NAME}"
  chmod +x "$BIN_PATH"
}

# 证书（不 echo，不创建 subshell）
[ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ] || {
  openssl req -x509 -nodes -newkey ec \
    -pkeyopt ec_paramgen_curve:prime256v1 \
    -days 3650 -keyout "$KEY_FILE" -out "$CERT_FILE" \
    -subj "/CN=${SNI}"
}

# YAML 内存压缩：低带宽 + 低窗口 + 单 stream
cat > server.yaml <<EOF
listen: ":${SERVER_PORT}"
tls:
  cert: "$CERT_FILE"
  key: "$KEY_FILE"
  alpn: ["${ALPN}"]
auth:
  type: password
  password: "${AUTH_PASSWORD}"
bandwidth:
  up: "30mbps"
  down: "30mbps"
quic:
  max_idle_timeout: "8s"
  max_concurrent_streams: 1
  initial_stream_receive_window: 32768
  max_stream_receive_window: 65536
  initial_conn_receive_window: 65536
  max_conn_receive_window: 131072
EOF

# 单次 curl，避免多余打印
IP=$(curl -fsS --max-time 4 https://api.ipify.org || echo "IP")

echo "IP: $IP  PORT: $SERVER_PORT"
echo "hysteria2://${AUTH_PASSWORD}@${IP}:${SERVER_PORT}?sni=${SNI}&alpn=${ALPN}&insecure=1"

exec "$BIN_PATH" server -c server.yaml
