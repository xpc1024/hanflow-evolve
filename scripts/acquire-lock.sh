#!/usr/bin/env bash
# acquire-lock.sh — LOOP 并发防护锁 (spec §8.6)
#
# 用法 (必须用 source, 因为设置了 trap 在调用 shell 退出时释放锁):
#     source scripts/acquire-lock.sh <evolve_home>
#
# 行为:
#   - 若 $EVOLVE_HOME/.loop.lock 不存在 → 创建并写入当前 PID
#   - 若存在但其中的 PID 已死 → 视为残留锁, 清除后重新获取
#   - 若存在且 PID 仍活 → 退出非 0, 提示已有 LOOP 在运行
#   - 设置 trap EXIT/INT/TERM, 调用 shell 退出时自动 rm 锁
#
# 注意: 本脚本通过 `source` 执行, 故不能 set -euo pipefail (会影响调用 shell)。
# 只在出错路径显式 exit 1。
EVOLVE_HOME="${1:?Usage: source acquire-lock.sh <evolve_home>}"
LOCK="$EVOLVE_HOME/.loop.lock"
if [ -f "$LOCK" ]; then
  PID=$(cat "$LOCK" 2>/dev/null || echo "")
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    echo "ERROR: LOOP 已在运行 (PID $PID). 如需强制启动, 先删除 $LOCK." >&2
    exit 1
  fi
  rm -f "$LOCK"
fi
echo $$ > "$LOCK"
_release_lock() { rm -f "$LOCK"; }
trap _release_lock EXIT INT TERM
