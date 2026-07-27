#!/usr/bin/env bash
# acquire-lock.sh — contribute-pr 并发防护锁 (spec §8.2)
#
# 用法 (必须用 source, 因为设置了 trap 在调用 shell 退出时释放锁):
#     source skills/contribute-pr/scripts/acquire-lock.sh <evolve_home>
#
# 行为:
#   - 若 $EVOLVE_HOME/.loop-contribute.lock 不存在 → 创建并写入当前 PID
#   - 若存在但其中的 PID 已死 → 视为残留锁, 清除后重新获取
#   - 若存在且 PID 仍活 → 退出非 0, 提示已有 contribute-pr 在运行
#   - 设置 trap EXIT/INT/TERM, 调用 shell 退出时自动 rm 锁
#
# 与 loop-evolve 的 .loop.lock 独立, 两者可并行 (维护者跑 loop-evolve, 贡献者跑 contribute-pr)。
#
# 注意: 本脚本通过 `source` 执行, 故不能 set -euo pipefail (会影响调用 shell)。
# 只在出错路径显式 exit 1。
EVOLVE_HOME="${1:?Usage: source acquire-lock.sh <evolve_home>}"
LOCK="$EVOLVE_HOME/.loop-contribute.lock"
if [ -f "$LOCK" ]; then
  PID=$(cat "$LOCK" 2>/dev/null || echo "")
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    echo "ERROR: contribute-pr 已在运行 (PID $PID). 如需强制启动, 先删除 $LOCK." >&2
    exit 1
  fi
  rm -f "$LOCK"
fi
echo $$ > "$LOCK"
_release_contribute_lock() { rm -f "$LOCK"; }
trap _release_contribute_lock EXIT INT TERM
