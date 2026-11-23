# dsh-harness-docker

DeepSeek Harness（`dsh`）+ Caddy（IP 白名单 + basic auth）+ Node.js 22 + Python 3 的 Docker 镜像。
Tailscale 用你自己已有的容器，本仓库只管 dsh 这一个容器。

## 架构

```
你的设备（远程走 Tailscale，到达 NAS 后等同局域网访问）
   │
   ▼
┌─ NAS ─────────────────────────────────────────────────┐
│  [你自己的 tailscale 容器]                              │
│                                                        │
│  [dsh 容器]  Caddy :8443 ──► dsh web 127.0.0.1:3080   │
│              │                                         │
│              ├─ 第1层：来源 IP 白名单（remote_ip）       │
│              └─ 第2层：basic auth（bcrypt）             │
│  Node 24 · Python 3.11 + uv · Go 1.25 · Git             │
└───────────────────────────────────────────────────────┘
   公网：无端口映射，不可达
```

- `dsh web` 只绑容器内 `127.0.0.1`，Caddy 是唯一入口
- 白名单默认放行内网网段 + Tailscale 网段（100.64.0.0/10）+ 回环，见下文「安全分层」

## 使用

### 1. 构建镜像

Push 到你的 GitHub 仓库即可，Actions 自动构建并推送 `ghcr.io/<你的用户名>/dsh-harness:latest`（amd64 + arm64，每周自动重建跟进 dsh 新版本）。

### 2. NAS 上部署

```bash
git clone https://github.com/<你的用户名>/dsh-harness-docker.git
cd dsh-harness-docker
cp .env.example .env
```

编辑 `.env`：

- `DSH_IMAGE` 改成 `ghcr.io/<你的用户名>/dsh-harness:latest`
- `CADDY_HASH`：`docker run --rm -it caddy:2 caddy hash-password` 生成后粘贴
- `ALLOWED_IPS`（可选）：留空用默认；收紧示例 `ALLOWED_IPS=192.168.1.23 100.64.0.0/10`

```bash
docker compose pull
docker compose up -d
```

浏览器访问 `http://<NAS局域网IP>:8443`（远程设备经 Tailscale 访问同一地址）。用户名 `dsh`，密码为你 hash 前的明文。

### 3. 接入你的本地 API 网关

两种方式任选：

- Web UI：Settings → Models → Add a custom provider，填 Base URL（含 `/v1`）、协议选 `openai-completions`、填 key
- 文件：把 `examples/settings.yaml` 复制到 `dsh-home/settings.yaml` 改网关地址，key 写入 `dsh-home/.credentials.yaml`（`chmod 600`）

数据都在挂载卷里：`workspace/`（项目代码）、`dsh-home/`（配置与凭据）。

## 安全分层（按单人使用设计）

| 层 | 措施 | 是否影响 NAS 其他应用 |
|---|---|---|
| 服务内 | Caddy `remote_ip` 白名单，默认内网+tailnet+回环，`.env` 可收紧 | 否（只作用于 8443 这一个端口） |
| 服务内 | Caddy basic auth（bcrypt，用户名 `dsh`） | 否 |
| 容器内 | `dsh web` 只绑 127.0.0.1，不直接暴露 | 否 |
| tailnet | **推荐**：在 Tailscale 管理台配 ACL，限定只有你的设备能访问 NAS | 否（ACL 只管 tailnet 流量） |
| NAS 防火墙 | **不推荐**：全局规则容易影响 NAS 上其他服务的入站 | 可能误伤 |

关于 SNAT：如果你的 Tailscale 容器做子网路由（默认开 SNAT），远程访问到 Caddy 时来源 IP 会变成 tailscale 容器的桥接地址，已包含在默认白名单 `172.16.0.0/12` 内；想要在 Caddy 里看到设备真实 tailnet IP（100.x），可在子网路由上关 SNAT（`--snat-subnet-routes=false`）。

## 更新

镜像由 CI 每周一自动重建；NAS 上手动更新：

```bash
docker compose pull && docker compose up -d
```

## 排障

- **403 Forbidden**：来源 IP 不在白名单。远程访问时先确认 Caddy 看到的来源 IP（`docker logs dsh` 里 Caddy 访问日志），必要时加进 `ALLOWED_IPS`
- **401 进不去**：确认用的是 `CADDY_HASH` 对应的明文密码，用户名固定为 `dsh`
- **模型 401 / MISSING_CREDENTIAL**：Base URL 必须含 `/v1`；key 未被读到时检查 `.credentials.yaml` 权限与变量名是否和 `apiKeyEnv` 一致
