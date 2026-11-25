#!/command/with-contenv sh
# oneshot：把换源丢到后台后立即退出，s6 不等待它，也不会杀掉它的子进程。
# 内置 chsrc：启动时按容器实际网络测速，把 apt/npm/pnpm/pip/uv/go 换到最快国内镜像。
# 手动重测：docker exec -u app -e HOME=/data/dsh-home -it dsh chsrc set <dish>；回官方源：chsrc reset <dish>
# 注意：本脚本由 s6-rc.d/chsrc-mirror/up 以 execline 包装调用；
# s6-rc 的 up 文件必须是 execline 而不是 shell（#! 在那里会被当注释忽略）。
if ! command -v chsrc >/dev/null 2>&1; then
  exit 0
fi
HOME_DIR="${DSH_HOME:-/data/dsh-home}"
echo "chsrc: 后台按实际网络测速换源中，详情 /var/log/chsrc.log"
(
  # debian 改的是 /etc/apt/sources.list，必须 root
  timeout 60 chsrc set debian || true

  # 其余都是用户级配置（~/.npmrc、~/.config/pnpm|pip|uv|go），必须以 app 身份写进 $HOME：
  # 用 root 写出来的是 600 root:root，降权后的 dsh 读不到就报
  #   [WARN] Issue while reading "/data/dsh-home/.npmrc". Permission denied
  # （app 用户由 user-setup 服务创建，本服务已在 s6-rc.d/chsrc-mirror/dependencies.d
  #  声明依赖，保证这里运行时用户与目录属主都已就绪）
  if [ "${PUID:-1000}" != "0" ]; then
    for d in npm pnpm pip uv go; do
      HOME="${HOME_DIR}" timeout 60 s6-setuidgid app chsrc set "${d}" || true
    done
  else
    for d in npm pnpm pip uv go; do
      HOME="${HOME_DIR}" timeout 60 chsrc set "${d}" || true
    done
  fi
) >>/var/log/chsrc.log 2>&1 &
exit 0
