#!/usr/bin/env bash
# async-api.sh — charter-check ④：IO 方法 async-first（spec §2 不变量 2, §4.3 ④）
#
# 用法: async-api.sh <hanflow_path> <mode: diff|full> <adr_dir>
# 在 models/persistence/tools/retrieval 包内，检查匹配 IO 方法名模式的公共函数
# 是否为 async def。范围收窄到 IO 方法名，避免误报合法的 sync 辅助函数。
# 退出: 0=通过; 1=有违规; 2=配置错误。
set -euo pipefail

HANFLOW_PATH="${1:?Usage: async-api.sh <hanflow_path> <mode> <adr_dir>}"
MODE="${2:?Usage: async-api.sh <hanflow_path> <mode> <adr_dir>}"
ADR_DIR="${3:?Usage: async-api.sh <hanflow_path> <mode> <adr_dir>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

# IO 方法名模式（明显是 IO 动词）
IO_METHODS='(complete|chat|embed|invoke|call|fetch|get|put|save|load|list|delete|search|upsert|retrieve|health|connect|close|stream)'

files=$(list_py_files "$HANFLOW_PATH" "$MODE")
total=$(echo "$files" | grep -c '.' || true)

violations=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  # 只检查 IO 包
  case "$f" in
    */hanflow/models/*|*/hanflow/persistence/*|*/hanflow/tools/*|*/hanflow/retrieval/*) : ;;
    *) continue ;;
  esac
  # 找 sync def 的公共 IO 方法（非 async、非私有 _）
  # 模式：行首缩进 + def + (IO动词)((_字串)或紧跟()
  # 例：def complete(、def get_tuple(、def search(；不匹配 async def、def _private(
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    lineno=$(echo "$line" | cut -d: -f1)
    content=$(echo "$line" | cut -d: -f2-)
    # 提取方法名（def 后到 ( 之前）
    methodname=$(echo "$content" | sed -E 's|.*def[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)\s*\(.*|\1|')
    [ "$methodname" = "$content" ] && continue  # 未匹配到 def，跳过
    # 私有豁免
    case "$methodname" in _*) continue ;; esac
    # 是否匹配 IO 方法名：以 IO 动词开头，后接 _ 或结束（用 $ 或 _ 界定，不用 \b）
    echo "$methodname" | grep -qE "^${IO_METHODS}(_|$)" || continue
    # 检查上方 2 行是否有 # sync-bridge 注释豁免
    prev=$(sed -n "$((lineno-1)),${lineno}p" "$f" 2>/dev/null | grep -E 'sync-bridge' || true)
    [ -n "$prev" ] && continue
    rel=${f#"$HANFLOW_PATH/"}
    violations+="  - ${rel}:${lineno}: def ${methodname}() 在 IO 模块应为 async def"$'\n'
  done < <(grep -nE "^[[:space:]]*def[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(" "$f" | grep -vE 'async[[:space:]]+def' || true)
done <<< "$files"

# 过滤白名单（含 LangGraph base stub：put/get_tuple/list）
final=""
while IFS= read -r v; do
  [ -z "$v" ] && continue
  relpath=$(echo "$v" | grep -oE 'hanflow/[^ :]+\.py' | head -1)
  if in_whitelist async "$relpath" "$ADR_DIR"; then
    continue
  fi
  final+="$v"$'\n'
done <<< "$violations"

vcount=$(echo "$final" | grep -c '.' || true)
if [ "$vcount" -eq 0 ]; then
  report_ok async-api "$total"
  exit 0
fi

report_fail async-api "$vcount"
echo -n "$final"
exit 1
