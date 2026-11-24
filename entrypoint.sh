#!/bin/sh
set -e

DSH_HOME="${DSH_HOME:-/data/dsh-home}"
mkdir -p "${DSH_HOME}"

# basic auth 优先级：CADDY_HASH（bcrypt）> 文件 secret /run/secrets/dsh_password
# > BASIC_AUTH_PASSWORD（明文）> 自动生成随机密码（持久化到 $DSH_HOME/INITIAL_PASSWORD.txt，重启沿用）
if [ -z "${CADDY_HASH}" ]; then
  PW_FILE="${DSH_HOME}/INITIAL_PASSWORD.txt"
  if [ -f /run/secrets/dsh_password ]; then
    PW="$(cat /run/secrets/dsh_password)"
  elif [ -n "${BASIC_AUTH_PASSWORD}" ]; then
    PW="${BASIC_AUTH_PASSWORD}"
  elif [ -f "${PW_FILE}" ]; then
    PW="$(cat "${PW_FILE}")"
  else
    PW="$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)"
    printf '%s\n' "${PW}" > "${PW_FILE}"
    chmod 600 "${PW_FILE}"
  fi
  CADDY_HASH="$(caddy hash-password --plaintext "${PW}")"
  export CADDY_HASH
  echo "=================================================="
  echo " dsh 入口密码已就绪"
  echo "   用户名: dsh"
  echo "   密码  : ${PW}"
  echo "   （已写入 ${PW_FILE}，重启沿用同一密码）"
  echo "=================================================="
fi

# 来源 IP 白名单默认值：内网网段（含 docker 桥接网段）+ Tailscale 网段 + 回环
# 说明：若你的 Tailscale 子网路由开了 SNAT（默认开），远程访问的来源 IP 会变成
# tailscale 容器的桥接 IP，已包含在 172.16.0.0/12 内；在 .env 设置 ALLOWED_IPS 可收紧
: "${ALLOWED_IPS:=192.168.0.0/16 10.0.0.0/8 172.16.0.0/12 100.64.0.0/10 127.0.0.1 ::1}"
export ALLOWED_IPS

# dsh web 自身还有一层浏览器认证：启动时打印带一次性 token 的 URL，浏览器首次访问
# 该 URL 换取会话 cookie；且它只信任 loopback / 绑定地址 / --trusted-host 点名的
# Host。经 Caddy 反代从外部访问时（浏览器 Host 是 NAS 地址），必须用 DSH_TRUSTED_HOSTS
# 把浏览器看到的地址加进信任列表，否则过完 basic auth 页面能开但每个 API 都 403。
# 两个 flag 都先探测当前 dsh 是否支持再传：dsh 由 CI 跟随上游更新，
# 老版本（--public-url 需 0.2.3-alpha.2+）不认这些参数会直接起不来。
DSH_ARGS=""
DSH_WEB_HELP="$(dsh web --help 2>&1 || true)"
for h in ${DSH_TRUSTED_HOSTS:-}; do
  case "${DSH_WEB_HELP}" in
    *--trusted-host*) DSH_ARGS="${DSH_ARGS} --trusted-host ${h}" ;;
    *) echo "WARNING: 当前 dsh 不支持 --trusted-host，忽略 DSH_TRUSTED_HOSTS（Host 栅栏将拒绝外部访问）" ;;
  esac
done
if [ -n "${DSH_PUBLIC_URL:-}" ]; then
  case "${DSH_WEB_HELP}" in
    *--public-url*) DSH_ARGS="${DSH_ARGS} --public-url ${DSH_PUBLIC_URL}" ;;
    *) echo "WARNING: 当前 dsh（<0.2.3-alpha.2）不支持 --public-url，已忽略 DSH_PUBLIC_URL；日志里的 token 地址指向容器内，请把 ?token=... 手工拼到外部地址访问" ;;
  esac
fi

mkdir -p /var/log/caddy
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
# shellcheck disable=SC2086
exec dsh web --port "${DSH_PORT:-3080}" ${DSH_ARGS}
