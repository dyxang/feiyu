# DeepSeek Harness (dsh) + Caddy + Node.js + Python + Go + uv
FROM caddy:2 AS caddy

# Go 1.26.x：1.25 的 stdlib 存在 HIGH CVE（crypto/tls、crypto/x509、net/http），需 ≥1.26.10
FROM golang:1.26-bookworm AS golang

FROM ghcr.io/astral-sh/uv:latest AS uv

FROM node:24-bookworm-slim

# 构建平台由 buildx 自动注入（CI 默认 linux/amd64；NAS 是 ARM 时在 workflow 改 platforms）
ARG TARGETARCH=amd64
# s6-overlay 版本（容器内 init/守护系统）：固定版本 + 官方 sha256 校验；升级只改这个数字
# renovate: datasource=github-releases depName=just-containers/s6-overlay versioning=loose
ARG S6_OVERLAY_VERSION=3.2.1.0

# 构建期 apt 走官方源（CI 在境外，走国内源反而慢）；运行时的换源交给内置的 chsrc。
# xz-utils 用于解压 s6-overlay；tini 已移除——1 号进程交给 s6 的 /init，
# 职责更全：信号转发 + 僵尸回收 + 各服务崩溃自动拉起
RUN apt-get update && apt-get install -y --no-install-recommends \
      xz-utils \
      git \
      openssh-client \
      ca-certificates \
      curl \
      python3 \
      python3-venv \
      python3-pip \
    && rm -rf /var/lib/apt/lists/*

# s6-overlay：caddy / dsh / chsrc-mirror 三个服务由它托管（服务定义在仓库 s6-overlay/ 目录）。
# 好处：崩溃自动拉起（带退避限速）、docker stop 按依赖优雅停机、软件级重启——
#   重启 dsh：       docker exec dsh s6-svc -r /run/service/dsh
#   停 / 启 dsh：    docker exec dsh s6-svc -d /run/service/dsh（-u 启动）
#   重载 Caddy 配置： docker exec dsh caddy reload --config /etc/caddy/Caddyfile
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64)   s6_arch=x86_64  ;; \
      arm64)   s6_arch=aarch64 ;; \
      arm)     s6_arch=armhf   ;; \
      riscv64) s6_arch=riscv64 ;; \
      *) echo "s6-overlay: 不支持的架构 ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    base="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}"; \
    curl -fsSL "${base}/s6-overlay-noarch.tar.xz" -o /tmp/s6-overlay-noarch.tar.xz; \
    curl -fsSL "${base}/s6-overlay-${s6_arch}.tar.xz" -o "/tmp/s6-overlay-${s6_arch}.tar.xz"; \
    curl -fsSL "${base}/s6-overlay-noarch.tar.xz.sha256" -o /tmp/s6-overlay-noarch.tar.xz.sha256; \
    curl -fsSL "${base}/s6-overlay-${s6_arch}.tar.xz.sha256" -o "/tmp/s6-overlay-${s6_arch}.tar.xz.sha256"; \
    ( cd /tmp && sha256sum -c "s6-overlay-noarch.tar.xz.sha256" "s6-overlay-${s6_arch}.tar.xz.sha256" ); \
    tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz --no-same-owner; \
    tar -C / -Jxpf "/tmp/s6-overlay-${s6_arch}.tar.xz" --no-same-owner; \
    rm -rf /tmp/s6-overlay-*

COPY --from=caddy /usr/bin/caddy /usr/bin/caddy
COPY --from=golang /usr/local/go /usr/local/go
COPY --from=uv /uv /uvx /usr/local/bin/
ENV PATH="/usr/local/go/bin:${PATH}"

# 先升级 npm：node:24 自带的 npm 11 捆了 undici 6.28.0 / brace-expansion 5.0.9（HIGH CVE），npm 12 已修复
# pnpm 预装进镜像，容器内开箱即用；三个 dsh 子包把 undici 精确锁死在 8.11.2（HIGH CVE 需 8.12.2），
# 精确版本无法用 overrides 修正，直接用 npm 官方 tarball 替换 dsh 下那份副本
# （与安装放在同一层：跨层删除不会回收下层空间，旧副本会以死重形式留在镜像里）
RUN set -eux; \
    npm install -g npm@latest; \
    npm install -g pnpm; \
    npm install -g @deepseek-ai/dsh; \
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

# 内置 chsrc（换源工具）：默认跟随 GitHub 最新正式版；CHSRC_VERSION 可固定版本。
# 放在 COPY 配置/服务脚本之前：配置或服务脚本改动不会触发重新下载 chsrc；
# CHSRC_REFRESH 由 CI 每次重置，避免构建缓存复用旧包，又能让拉取失败只影响这一层。
ARG CHSRC_VERSION=latest
ARG CHSRC_REFRESH=0
RUN set -eux; \
    echo "chsrc: version=${CHSRC_VERSION} refresh=${CHSRC_REFRESH}"; \
    case "${TARGETARCH}" in \
      amd64) chsrc_arch=x64 ;; \
      arm64) chsrc_arch=aarch64 ;; \
      arm)   chsrc_arch=armv7 ;; \
      riscv64) chsrc_arch=riscv64 ;; \
      *) echo "chsrc: 不支持的架构 ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    if [ "${CHSRC_VERSION}" = "latest" ]; then \
      want="https://github.com/RubyMetric/chsrc/releases/latest/download/chsrc-${chsrc_arch}-linux"; \
      spare="https://gitee.com/RubyMetric/chsrc/releases/download/pre/chsrc-${chsrc_arch}-linux"; \
    else \
      want="https://github.com/RubyMetric/chsrc/releases/download/${CHSRC_VERSION}/chsrc-${chsrc_arch}-linux"; \
      spare="https://gitee.com/RubyMetric/chsrc/releases/download/${CHSRC_VERSION}/chsrc-${chsrc_arch}-linux"; \
    fi; \
    if ! curl -fsSL "$want" -o /usr/local/bin/chsrc; then \
      curl -fsSL "$spare" -o /usr/local/bin/chsrc; \
    fi; \
    chmod +x /usr/local/bin/chsrc; \
    chsrc --version

COPY Caddyfile /etc/caddy/Caddyfile
COPY --chmod=0755 s6-overlay/ /etc/s6-overlay/

# 仅 Caddy 对外；dsh 只绑容器内 127.0.0.1
EXPOSE 8443

# 任意 HTTP 响应（含 401）即视为存活
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -s -o /dev/null http://127.0.0.1:8443/ || exit 1

# s6-overlay 的 /init 作为 1 号进程：启动时编译服务库、按依赖顺序启停、
# 把 docker stop 的 SIGTERM 转发给每个服务并回收僵尸进程
ENTRYPOINT ["/init"]
