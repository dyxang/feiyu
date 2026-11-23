# DeepSeek Harness (dsh) + Caddy + Node.js + Python + Go + uv
FROM caddy:2 AS caddy

# Go 1.26.x：1.25 的 stdlib 存在 HIGH CVE（crypto/tls、crypto/x509、net/http），需 ≥1.26.10
FROM golang:1.26-bookworm AS golang

FROM ghcr.io/astral-sh/uv:latest AS uv

FROM node:24-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      tini \
      git \
      ca-certificates \
      curl \
      python3 \
      python3-venv \
      python3-pip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=caddy /usr/bin/caddy /usr/bin/caddy
COPY --from=golang /usr/local/go /usr/local/go
COPY --from=uv /uv /uvx /usr/local/bin/
ENV PATH="/usr/local/go/bin:${PATH}"

# 先升级 npm：node:24 自带的 npm 11 捆了 undici 6.28.0 / brace-expansion 5.0.9（HIGH CVE），npm 12 已修复
RUN npm install -g npm@latest \
 && npm install -g @deepseek-ai/dsh

# 三个 dsh 子包把 undici 精确锁死在 8.11.2（HIGH CVE 需 8.12.2），精确版本无法用 overrides 修正，
# 直接用 npm 官方 tarball 替换 dsh 下那份副本
RUN set -eux; \
    tmp="$(mktemp -d)"; \
    cd "$tmp"; \
    npm pack undici@8.12.2 >/dev/null; \
    tar xzf undici-8.12.2.tgz; \
    target="$(npm root -g)/@deepseek-ai/dsh/node_modules"; \
    rm -rf "$target/undici"; \
    mv package "$target/undici"; \
    cd /; rm -rf "$tmp"

ENV DSH_HOME=/data/dsh-home
WORKDIR /data/workspace

COPY Caddyfile /etc/caddy/Caddyfile
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 仅 Caddy 对外；dsh 只绑容器内 127.0.0.1
EXPOSE 8443

# 任意 HTTP 响应（含 401）即视为存活
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -s -o /dev/null http://127.0.0.1:8443/ || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
