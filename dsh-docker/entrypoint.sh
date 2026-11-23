#!/bin/sh
set -e

# basic auth：优先 CADDY_HASH（bcrypt），否则用 BASIC_AUTH_PASSWORD 现场生成
if [ -z "${CADDY_HASH}" ] && [ -n "${BASIC_AUTH_PASSWORD}" ]; then
  CADDY_HASH="$(caddy hash-password --plaintext "${BASIC_AUTH_PASSWORD}")"
  export CADDY_HASH
fi
if [ -z "${CADDY_HASH}" ]; then
  echo "ERROR: 请设置 CADDY_HASH（生成：docker run --rm caddy:2 caddy hash-password）或 BASIC_AUTH_PASSWORD" >&2
  exit 1
fi

# 来源 IP 白名单默认值：内网网段（含 docker 桥接网段）+ Tailscale 网段 + 回环
# 说明：若你的 Tailscale 子网路由开了 SNAT（默认开），远程访问的来源 IP 会变成
# tailscale 容器的桥接 IP，已包含在 172.16.0.0/12 内；在 .env 设置 ALLOWED_IPS 可收紧
: "${ALLOWED_IPS:=192.168.0.0/16 10.0.0.0/8 172.16.0.0/12 100.64.0.0/10 127.0.0.1 ::1}"
export ALLOWED_IPS

mkdir -p "${DSH_HOME:-/data/dsh-home}"

caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
exec dsh web --port "${DSH_PORT:-3080}"
