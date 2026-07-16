#!/usr/bin/env bash
# pydantic-data.sh — charter-check ⑤：结构化数据走 Pydantic（spec §2 不变量 3, §4.3 ⑤）
#
# 用法: pydantic-data.sh <hanflow_path> <mode: diff|full> <adr_dir>
# 检查 @dataclass 装饰的类，若类名含 Config/State/Schema/Spec/Request/Response → 违规。
# 白名单：@dataclass(frozen=True) 纯值对象；测试替身（FakeContext/_FakeSpan）。
# 退出: 0=通过; 1=有违规; 2=配置错误。
set -euo pipefail

HANFLOW_PATH="${1:?Usage: pydantic-data.sh <hanflow_path> <mode> <adr_dir>}"
MODE="${2:?Usage: pydantic-data.sh <hanflow_path> <mode> <adr_dir>}"
ADR_DIR="${3:?Usage: pydantic-data.sh <hanflow_path> <mode> <adr_dir>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

# Config/State/Schema 语义类名模式
SEMANTIC='(Config|State|Schema|Spec|Request|Response)'

files=$(list_py_files "$HANFLOW_PATH" "$MODE")
total=$(echo "$files" | grep -c '.' || true)

violations=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  # 找 @dataclass 装饰的类。dataclass 可能在前一行或同行。
  # 策略：找 "class \w+SEMANTIC" 定义，检查其上方 1-2 行是否有 @dataclass。
  while IFS= read -r classline; do
    [ -z "$classline" ] && continue
    lineno=$(echo "$classline" | cut -d: -f1)
    content=$(echo "$classline" | cut -d: -f2-)
    classname=$(echo "$content" | grep -oE 'class\s+\w+' | head -1 | awk '{print $2}')
    # 私有类豁免
    case "$classname" in
      _*) continue ;;
    esac
    # 测试替身豁免
    case "$classname" in
      Fake*|*Fake|Mock*|*Mock|Stub*|*Stub) continue ;;
    esac
    # 检查上方 1-2 行是否有 @dataclass
    prev1=$(sed -n "$((lineno-1))p" "$f" 2>/dev/null || true)
    prev2=$(sed -n "$((lineno-2))p" "$f" 2>/dev/null || true)
    if echo "$prev1$prev2" | grep -qE '@dataclass'; then
      # frozen=True 纯值对象豁免
      if echo "$prev1$prev2" | grep -qE 'frozen[[:space:]]*=[[:space:]]*True'; then
        continue
      fi
      rel=${f#"$HANFLOW_PATH/"}
      violations+="  - ${rel}:${lineno}: @dataclass class ${classname}  → 应用 BaseModel + ConfigDict"$'\n'
    fi
  done < <(grep -nE "class\s+\w+${SEMANTIC}\b" "$f" || true)
done <<< "$files"

# 过滤白名单
final=""
while IFS= read -r v; do
  [ -z "$v" ] && continue
  relpath=$(echo "$v" | grep -oE 'hanflow/[^ :]+\.py' | head -1)
  if in_whitelist pydantic "$relpath" "$ADR_DIR"; then
    continue
  fi
  final+="$v"$'\n'
done <<< "$violations"

vcount=$(echo "$final" | grep -c '.' || true)
if [ "$vcount" -eq 0 ]; then
  report_ok pydantic-data "$total"
  exit 0
fi

report_fail pydantic-data "$vcount"
echo -n "$final"
exit 1
