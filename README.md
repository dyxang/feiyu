# dsh-harness-docker

DeepSeek Harness（`dsh`）+ Caddy（IP 白名单 + basic auth）+ Node.js 24 + Python 3.11（uv 可按项目装任意新版）+ Go 1.25 的 Docker 镜像。
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

### 快速开始（只改一处）

1. **出镜像**：把本仓库 push 到你的 GitHub，等 Actions 首次构建完成（绿勾）。之后 CI 每周一自动重建（拉最新底座补丁与 dsh 新版）→ Trivy 漏洞扫描（发现 HIGH/CRITICAL 时该次运行标红）；默认仅 linux/amd64，NAS 是 ARM 时在 workflow 里把 platforms 改成 `linux/amd64,linux/arm64`。
2. **部署**：NAS 上新建一个文件夹，把 `docker-compose.yml` 拷进去——文件顶部注释就是完整步骤。把 `image:` 行里的 `your-name` 换成你的 GitHub 用户名（或同目录建 `.env` 设 `DSH_IMAGE`），然后：

   ```bash
   docker compose up -d
   ```

3. **进入**：浏览器打开 `http://<NAS局域网IP>:8443`（远程设备经 Tailscale 访问同一地址）。用户名 `dsh`，密码：

   ```bash
   cat data/dsh-home/INITIAL_PASSWORD.txt   # 或 docker logs dsh
   ```

   注意：`dsh web` 在 basic auth 之内还有自己的一层浏览器认证，首次进入（及每次重启容器后）需要用启动日志里带 token 的地址换取会话 cookie，见下文「DSH_TRUSTED_HOSTS」与排障第 3 条。

首次进入 Web UI：Settings → Models → Add a custom provider 接入你的本地 API 网关（Base URL 含 `/v1`、协议选 `openai-completions`、填 key）。文件方式参考 `examples/settings.yaml`：复制到 `data/dsh-home/settings.yaml`，key 写入 `data/dsh-home/.credentials.yaml`（`chmod 600`）。

### 可选配置（不改也能用，compose 里有对应注释）

| 想做的事 | 怎么做 |
|---|---|
| 自己定入口密码 | 三选一（按安全排序）：文件 secret（见 compose 注释，inspect 不可见）＞ `.env` 设 `BASIC_AUTH_PASSWORD` ＞ `.env` 设 `CADDY_HASH`（bcrypt）；都不设 = 自动生成，写入 `data/dsh-home/INITIAL_PASSWORD.txt` |
| 主动换密码（如怀疑泄露） | 删除 `data/dsh-home/INITIAL_PASSWORD.txt` 后 `docker compose up -d`，自动生成新密码 |
| 收紧 IP 白名单 | `.env` 里设 `ALLOWED_IPS`，例如 `ALLOWED_IPS=192.168.1.23 100.64.0.0/10` |
| 过 dsh 自己那层认证 | `.env` 里设 `DSH_TRUSTED_HOSTS`（浏览器地址栏里的主机名/IP，空格分隔），并设 `DSH_PUBLIC_URL=http://<NAS局域网IP>:8443` 让启动日志直接打印可点开的带 token 地址 |
| 只绑指定网卡 | compose 里 ports 改成 `"<NAS局域网IP>:8443:8443"` |
| 换镜像源/回官方源 | compose 的 `environment:` 里覆盖对应变量：`NPM_CONFIG_REGISTRY`（npm/pnpm）、`GOPROXY`（go）、`PIP_INDEX_URL`（pip）、`UV_DEFAULT_INDEX`（uv）；官方源分别为 `https://registry.npmjs.org`、`https://proxy.golang.org,direct`、`https://pypi.org/simple`、`https://pypi.org/simple` |
| 缓存持久化 | 解开 compose 里 `go-cache` / `uv` 两行注释 |

NAS 上的目录结构（挂载均为 compose 相对路径，相对 docker-compose.yml 所在目录）：

```
dsh-harness-docker/      # 你新建的部署文件夹（名字随意）
├── docker-compose.yml   # 从本仓库拷入的部署文件
├── .env                 # 可选，不建也行
├── codespace/           # 代码持久化：dsh 工作区根目录（项目放这里）
└── data/
    └── dsh-home/        # 数据持久化：settings.yaml / .credentials.yaml / INITIAL_PASSWORD.txt
```

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

镜像由 CI 每周一自动重建（拉最新底座补丁与 dsh 新版），Trivy 扫描发现 HIGH/CRITICAL 漏洞时该次运行标红，看到后 `docker compose pull` 前先确认下个版本是否已修；NAS 上手动更新：

```bash
docker compose pull && docker compose up -d
```

组件版本与官方支持窗口（升级 = 改 Dockerfile 里对应 tag）：

| 组件 | 版本 | 官方支持到 |
|---|---|---|
| Node.js | 24 LTS | 2028-04 |
| Python | 3.11（Debian 维护，补丁回移植） | 2028-06（更新版用 uv 按项目装） |
| Go | 1.25 | 2027-02 |
| Debian 底座 | 12 bookworm | 2028 |
| dsh / uv / Caddy / pnpm | 跟随上游 | 每周重建自动跟进 |

镜像已内置国内镜像源默认值（容器内 `npm`/`pnpm` → 淘宝 npmmirror，`go get` → 七牛 goproxy.cn，`pip`/`uv` → 清华 PyPI），构建期不受影响；换源见「可选配置」。

## 排障

- **403 Forbidden**：来源 IP 不在白名单。远程访问时先确认 Caddy 看到的来源 IP（`docker logs dsh` 里 Caddy 访问日志），必要时加进 `ALLOWED_IPS`
- **401 进不去**：自动生成时密码在 `data/dsh-home/INITIAL_PASSWORD.txt`，或你 `.env` 里设置的密码；用户名固定为 `dsh`
- **"dsh web authentication required; reopen the URL printed by dsh web"**：这是 `dsh web` 自己的浏览器认证（在 Caddy basic auth 之内还有一层），不是密码错了。它有两道门：
  1. **Host 信任栅栏**：`dsh web` 只信任 loopback、绑定地址和 `--trusted-host` 点名的地址。你从浏览器经 Caddy 访问时 Host 是 NAS 地址，不在列表里——页面能开，但每个 API 调用都 403（如 `llm/listProviders failed: HTTP 403`）。解法：`.env` 设 `DSH_TRUSTED_HOSTS=192.168.1.23 100.101.102.103`（填你地址栏里实际用的主机名/IP，host 或 host:port，不带端口匹配任意端口，空格分隔多个），重建镜像并 `docker compose up -d`（entrypoint 会自动探测 dsh 版本并透传）。
  2. **一次性启动 token**：`dsh web` 每次启动都生成新 token 并打印在日志里，浏览器首次访问带 token 的 URL 会换取会话 cookie，之后正常访问。解法：`docker logs dsh | grep "dsh web:"` 找到打印的地址，把其中 `?token=...` 手工拼到你自己的外部地址后面打开一次。设了 `DSH_PUBLIC_URL`（需 dsh ≥0.2.3-alpha.2，当前 latest 0.2.2-rc.5 不支持、会被自动忽略）时，日志打印的就是可直接点开的外部地址。
  每次重启容器 token 都会变，若又出现这个提示，重新取一次日志里的地址即可。
- **模型 401 / MISSING_CREDENTIAL**：Base URL 必须含 `/v1`；key 未被读到时检查 `.credentials.yaml` 权限与变量名是否和 `apiKeyEnv` 一致
