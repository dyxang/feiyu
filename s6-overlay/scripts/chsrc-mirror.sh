#!/command/with-contenv sh
# oneshot：把换源丢到后台后立即退出，s6 不等待它，也不会杀掉它的子进程。
# 内置 chsrc：启动时按容器实际网络测速，把 apt/npm/pnpm/pip/uv/go 换到最快国内镜像。
# 手动重测：docker exec -it dsh chsrc set <dish>；回官方源：chsrc reset <dish>
# 注意：本脚本由 s6-rc.d/chsrc-mirror/up 以 execline 包装调用；
# s6-rc 的 up 文件必须是 execline 而不是 shell（#! 在那里会被当注释忽略）。
if ! command -v chsrc >/dev/null 2>&1; then
  exit 0
fi
echo "chsrc: 后台按实际网络测速换源中，详情 /var/log/chsrc.log"
(
  for d in debian npm pnpm pip uv go; do
    timeout 60 chsrc set "${d}" || true
  done
) >>/var/log/chsrc.log 2>&1 &
exit 0
