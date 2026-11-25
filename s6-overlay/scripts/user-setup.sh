#!/command/with-contenv sh
# oneshot：按 PUID/PGID 准备非 root 运行身份，caddy / dsh 都声明了本服务为依赖，
# s6-rc 会先跑完这里再起它们。PUID=0 时跳过，保持 root 运行（兼容旧行为）。
# 注意：不要用 compose 的 user: 指定身份——s6 init 需要 root 才能完成建号与降权。
# 注意：本脚本由 s6-rc.d/user-setup/up 以 execline 包装调用；
# s6-rc 的 up 文件必须是 execline 而不是 shell（#! 在那里会被当注释忽略）。
set -e
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
[ "${PUID}" = "0" ] && exit 0

DSH_HOME_DIR="${DSH_HOME:-/data/dsh-home}"
mkdir -p "${DSH_HOME_DIR}" /data/workspace

# 主组不存在就建；app 用户保证存在（-o 允许与宿主机同 uid 的其他账号共存），
# HOME 指向 dsh-home：node/npm/caddy 的缓存与点文件都落在持久卷里
if ! getent group "${PGID}" >/dev/null 2>&1; then
  groupadd -g "${PGID}" app
fi
if ! getent passwd app >/dev/null 2>&1; then
  useradd -o -u "${PUID}" -g "${PGID}" -d "${DSH_HOME_DIR}" -s /bin/sh app
elif [ "$(id -u app)" != "${PUID}" ]; then
  usermod -u "${PUID}" -g "${PGID}" app
fi

# dsh-home 是小体量配置目录（settings/凭据/密码/缓存），每次启动递归接管，保证可写；
# workspace 只接管顶层——递归 chown 大仓库很慢，也未必符合用户意图，
# 旧目录属主不对时请自行 chown 或把 PUID 设成宿主机目录属主
chown -R "${PUID}:${PGID}" "${DSH_HOME_DIR}" 2>/dev/null || \
  echo "WARNING: chown ${DSH_HOME_DIR} 失败（NFS root_squash / 挂载只读？）；若服务因权限崩溃请检查宿主机目录所有权"
chown "${PUID}:${PGID}" /data/workspace 2>/dev/null || true
