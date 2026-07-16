#!/usr/bin/env bash
# layering.sh — charter-check ①：14×14 依赖方向矩阵（spec §3, §4.3 ①）
#
# 用法: layering.sh <hanflow_path> <mode: diff|full> <adr_dir>
# 扫描 `from hanflow.X.` / `import hanflow.X`，解析 (caller_pkg, callee_pkg)，
# 查 CHARTER §3 矩阵，命中 ✗ → 违规。
# 退出: 0=通过; 1=有违规; 2=配置错误。
set -euo pipefail

HANFLOW_PATH="${1:?Usage: layering.sh <hanflow_path> <mode> <adr_dir>}"
MODE="${2:?Usage: layering.sh <hanflow_path> <mode> <adr_dir>}"
ADR_DIR="${3:?Usage: layering.sh <hanflow_path> <mode> <adr_dir>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

# 合法依赖表：caller_pkg 允许依赖的 callee_pkg 集合。
# 与 CHARTER §3 矩阵一致。core 被所有依赖；runtime/api/cli 是组合根可依赖全部 L4。
PKG_LIST="core atoms orchestration models memory runtime isolation persistence tools retrieval observability workflows api cli"

# is_allowed <caller> <callee>
# 规则：caller==callee 合法；callee==core 合法；runtime/api/cli 可依赖所有；
# 否则查白名单（各包只允许 core + self）。
is_allowed() {
  local caller="$1" callee="$2"
  [ "$caller" = "$callee" ] && return 0
  [ "$callee" = "core" ] && return 0
  case "$caller" in
    runtime|api|cli) return 0 ;;  # 组合根
    *) return 1 ;;                 # 其余只允许 core + self
  esac
}

files=$(list_py_files "$HANFLOW_PATH" "$MODE")
total=$(echo "$files" | grep -c '.' || true)

violations=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  # 调用方包名：从文件路径提取 hanflow/<pkg>/ 的 <pkg>
  caller_pkg=$(echo "$f" | grep -oE 'hanflow/[^/]+/' | head -1 | tr -d '/' | sed 's|hanflow||' || true)
  # 跳过 hanflow 顶层模块（config.py/sdk.py）——按组合根对待，不报
  [ -z "$caller_pkg" ] && continue
  # 扫描 import 语句
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    lineno=$(echo "$line" | cut -d: -f1)
    content=$(echo "$line" | cut -d: -f2-)
    # 提取 callee 包：from hanflow.<pkg>. 或 import hanflow.<pkg>
    callee_pkg=$(echo "$content" | grep -oE 'hanflow\.[a-z_]+' | head -1 | sed 's|hanflow\.||' || true)
    [ -z "$callee_pkg" ] && continue
    # 校验 callee 在已知包列表
    echo "$PKG_LIST" | grep -qw "$callee_pkg" || continue
    if ! is_allowed "$caller_pkg" "$callee_pkg"; then
      rel=${f#"$HANFLOW_PATH/"}
      violations+="  - ${rel}:${lineno}: ${caller_pkg} → ${callee_pkg} 非法依赖；应经 ctx 访问（CHARTER §3）"$'\n'
    fi
  done < <(grep -nE '^[[:space:]]*(from|import)[[:space:]]+hanflow\.' "$f" || true)
done <<< "$files"

# 过滤白名单
final=""
while IFS= read -r v; do
  [ -z "$v" ] && continue
  relpath=$(echo "$v" | grep -oE 'hanflow/[^ :]+\.py' | head -1)
  if in_whitelist layering "$relpath" "$ADR_DIR"; then
    continue
  fi
  final+="$v"$'\n'
done <<< "$violations"

vcount=$(echo "$final" | grep -c '.' || true)
if [ "$vcount" -eq 0 ]; then
  report_ok layering "$total"
  exit 0
fi

report_fail layering "$vcount"
echo -n "$final"
exit 1
