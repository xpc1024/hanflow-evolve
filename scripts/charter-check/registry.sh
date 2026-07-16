#!/usr/bin/env bash
# registry.sh — charter-check ③：节点分派走 registry 不硬编码（spec §2 不变量 4, §4.3 ③）
#
# 用法: registry.sh <hanflow_path> <mode: diff|full> <adr_dir>
# 在 orchestration/compiler、orchestration/node_executor_registry、orchestration/registry 模块内
# 检测 `if/elif .type ==` 或 `match .type:` 的节点类型硬编码分派反模式。
# 退出: 0=通过; 1=有违规; 2=配置错误。
#
# 已知缺口：dict 字典分派（{"foo": handler}）不走 registry 时 grep 抓不到。
# v1 接受此盲区；若成逃逸通道，经 ADR 升级为 Python AST 检查器。
set -euo pipefail

HANFLOW_PATH="${1:?Usage: registry.sh <hanflow_path> <mode> <adr_dir>}"
MODE="${2:?Usage: registry.sh <hanflow_path> <mode> <adr_dir>}"
ADR_DIR="${3:?Usage: registry.sh <hanflow_path> <mode> <adr_dir>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

files=$(list_py_files "$HANFLOW_PATH" "$MODE")
total=$(echo "$files" | grep -c '.' || true)

violations=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  # 只检查 orchestration 目录下的 compiler / registry 相关模块
  # （文件名含 compiler/registry 的模块均属于分派关注面）
  case "$f" in
    */orchestration/compiler.py|*/orchestration/registry.py|*/orchestration/node_executor_registry.py|*/orchestration/compiler/*.py|*/orchestration/*compiler*.py|*/orchestration/*registry*.py) : ;;
    *) continue ;;
  esac
  # 反模式：if/elif 后跟 .type == "字面量" 或 match .type:
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    lineno=$(echo "$line" | cut -d: -f1)
    content=$(echo "$line" | cut -d: -f2-)
    rel=${f#"$HANFLOW_PATH/"}
    violations+="  - ${rel}:${lineno}: ${content}  → 节点分派应走 registry（@register_node），不要硬编码 if/elif .type =="$'\n'
  done < <(grep -nE '(if|elif)[[:space:]].*\.type[[:space:]]*==[[:space:]]*["'\'']|match[[:space:]]+.*\.type[[:space:]]*:' "$f" || true)
done <<< "$files"

# 过滤白名单
final=""
while IFS= read -r v; do
  [ -z "$v" ] && continue
  relpath=$(echo "$v" | grep -oE 'hanflow/[^ :]+\.py' | head -1)
  if in_whitelist registry "$relpath" "$ADR_DIR"; then
    continue
  fi
  final+="$v"$'\n'
done <<< "$violations"

vcount=$(echo "$final" | grep -c '.' || true)
if [ "$vcount" -eq 0 ]; then
  report_ok registry "$total"
  exit 0
fi

report_fail registry "$vcount"
echo -n "$final"
exit 1
