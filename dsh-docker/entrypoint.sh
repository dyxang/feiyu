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

mkdir -p "${DSH_HOME:-/data/dsh-home}"

caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
exec dsh web --port "${DSH_PORT:-3080}"
