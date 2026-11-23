# dsh-harness-docker

DeepSeek Harness（`dsh`）+ Caddy basic auth + Node.js 22 + Python 3 的 Docker 镜像。
远程访问**仅通过 Tailscale**，不向公网或局域网映射任何端口。

## 架构

```
你的设备（任意地点，装 Tailscale 客户端）
   │  WireGuard 加密
   ▼
┌─ NAS ─────────────────────────────────────────────┐
│  [容器1] tailscale  ←  tailnet IP (100.x.x.x)      │
│     ▲ network_mode: service:tailscale（共享网络栈） │
│  [容器2] dsh:  Caddy :8443 ──► dsh web 127.0.0.1:3080 │
│          Node 22 · Python 3 · Git                  │
└───────────────────────────────────────────────────┘
   公网/局域网：无端口映射，不可达
```

- `dsh web` 只绑容器内 `127.0.0.1`，Caddy 是唯一入口
- Caddy basic auth 为第二道防线（tailnet 内其他设备失守时兜底）
- Tailscale 自带加密，内网环境无需 TLS；如需浏览器无警告 HTTPS，可在 Caddyfile 用 `tls internal`

## 使用

### 1. 构建镜像

Push 到你的 GitHub 仓库即可，Actions 会自动构建并推送 `ghcr.io/<你的用户名>/dsh-harness:latest`（amd64 + arm64，每周自动重建跟进 dsh 新版本）。

### 2. NAS 上部署

```bash
git clone https://github.com/<你的用户名>/dsh-harness-docker.git
cd dsh-harness-docker
cp .env.example .env
```

编辑 `.env`：

- `DSH_IMAGE` 改成 `ghcr.io/<你的用户名>/dsh-harness:latest`
- `CADDY_HASH`：`docker run --rm -it caddy:2 caddy hash-password` 生成后粘贴
- `TAILSCALE_AUTHKEY`：在 [Tailscale 管理台](https://login.tailscale.com/admin/settings/keys) 生成（选 reusable）

```bash
docker compose pull
docker compose up -d
```

启动后用 `docker logs dsh-tailscale` 查看 tailnet IP，浏览器访问：

```
http://<tailnet-ip>:8443
```

用户名 `dsh`，密码为你 hash 前的明文。

### 3. 接入你的本地 API 网关

两种方式任选：

- Web UI：Settings → Models → Add a custom provider，填 Base URL（含 `/v1`）、协议选 `openai-completions`、填 key
- 文件：把 `examples/settings.yaml` 复制到 `dsh-home/settings.yaml` 改网关地址，key 写入 `dsh-home/.credentials.yaml`（`chmod 600`）

数据都在挂载卷里：`workspace/`（项目代码）、`dsh-home/`（配置与凭据）、`tailscale-state/`。

## 更新

镜像由 CI 每周一自动重建；NAS 上手动更新：

```bash
docker compose pull && docker compose up -d
```

## 排障

- **NAS 无 `/dev/net/tun`**：部分 NAS 需要在管理台开启 TUN；实在不行设 `TS_USERSPACE=true` 并删掉 tun 挂载，同时需 `tailscale serve` 转发入站端口
- **401 进不去**：确认用的是 `CADDY_HASH` 对应的明文密码，用户名固定为 `dsh`
- **模型 401 / MISSING_CREDENTIAL**：Base URL 必须含 `/v1`；key 未被读到时检查 `.credentials.yaml` 权限与变量名是否和 `apiKeyEnv` 一致

## 安全边界（按单人使用设计）

| 层 | 措施 |
|---|---|
| 网络 | 无公网/局域网端口映射，仅 tailnet IP 可达；可在 Tailscale ACL 里进一步限定仅你的设备 |
| 入口 | Caddy basic auth（bcrypt） |
| 凭据 | API key 只存 `dsh-home/.credentials.yaml`，不进镜像不进 git；`.env` 已 gitignore |
