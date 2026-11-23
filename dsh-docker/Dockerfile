# DeepSeek Harness (dsh) + Caddy + Node.js + Python
FROM caddy:2 AS caddy

FROM node:22-bookworm-slim

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

RUN npm install -g @deepseek-ai/dsh

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
