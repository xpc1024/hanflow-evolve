#!/usr/bin/env bash
# errors.sh — charter-check ②：统一错误继承（spec §2 不变量 1, §4.3 ②）
#
# 用法: errors.sh <hanflow_path> <mode: diff|full> <adr_dir>
# 检查所有 `class \w+Error` 是否继承 HanflowError。
# 白名单：stdlib/三方异常自动豁免；hanflow/core/errors.py 豁免（基类定义处）。
# 退出: 0=通过; 1=有违规; 2=配置错误。
set -euo pipefail

HANFLOW_PATH="${1:?Usage: errors.sh <hanflow_path> <mode> <adr_dir>}"
MODE="${2:?Usage: errors.sh <hanflow_path> <mode> <adr_dir>}"
ADR_DIR="${3:?Usage: errors.sh <hanflow_path> <mode> <adr_dir>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

# stdlib / 三方异常白名单（继承这些具体 stdlib 异常的类不强制继承 HanflowError）
# 注：不含 Exception/BaseException 根类 —— 直接继承根 Exception 正是 charter 禁止的，
# 应改继承 HanflowError（它本身已是 Exception 子类）。仅豁免携带特殊语义的具体子类。
STDLIB_ERRORS="ValueError|TypeError|RuntimeError|KeyError|"
STDLIB_ERRORS+="AttributeError|IndexError|StopIteration|NotImplementedError|"
STDLIB_ERRORS+="OSError|IOError|FileNotFoundError|ConnectionError|TimeoutError|"
STDLIB_ERRORS+="ImportError|ModuleNotFoundError|LookupError|NameError|"
STDLIB_ERRORS+="ArithmeticError|ZeroDivisionError|OverflowError|"
STDLIB_ERRORS+="PermissionError|IsADirectoryError|JSONDecodeError|HTTPError|RequestException"

files=$(list_py_files "$HANFLOW_PATH" "$MODE")
total=$(echo "$files" | grep -c '.' || true)

# 收集违规：class \w+Error 且基类不含 HanflowError 且基类不在 stdlib 白名单
violations=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  # 跳过基类定义处
  case "$f" in
    */core/errors.py) continue ;;
  esac
  # grep 所有 class XxxError 定义行
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    lineno=$(echo "$line" | cut -d: -f1)
    content=$(echo "$line" | cut -d: -f2-)
    # 提取基类（class Name(Base1, Base2): 的括号内，去空格）
    bases=$(echo "$content" | grep -oE '\(([^)]*)\)' | tr -d '()' | tr -d ' ' || true)
    # 无基类（class FooError: ）→ 不强制（可能是 mixin/标记类），跳过
    [ -z "$bases" ] && continue
    # 若已继承 HanflowError → 合规
    if echo "$bases" | grep -qE '(^|,)HanflowError(,|$)'; then
      continue
    fi
    # 若所有基类都在 stdlib 白名单 → 豁免（纯 stdlib 派生）
    # 拆分逗号，逐个检查是否都在 STDLIB_ERRORS
    all_stdlib=1
    IFS=',' read -ra base_arr <<< "$bases"
    for b in "${base_arr[@]}"; do
      [ -z "$b" ] && continue
      if ! echo "$b" | grep -qE "^($STDLIB_ERRORS)$"; then
        all_stdlib=0
        break
      fi
    done
    [ "$all_stdlib" -eq 1 ] && continue
    # 命中违规（含非 stdlib 非 HanflowError 的自定义基类）
    rel=${f#"$HANFLOW_PATH/"}
    violations+="  - ${rel}:${lineno}: ${content}  → 未继承 HanflowError"$'\n'
  done < <(grep -nE '^\s*class\s+\w*Error\b' "$f" || true)
done <<< "$files"

# 过滤白名单（ADR）
final=""
while IFS= read -r v; do
  [ -z "$v" ] && continue
  # 提取 rel path 部分（"  - hanflow/xxx.py:N: ..."）用于白名单匹配
  relpath=$(echo "$v" | grep -oE 'hanflow/[^ :]+\.py' | head -1)
  if in_whitelist errors "$relpath" "$ADR_DIR"; then
    continue  # 白名单放行
  fi
  final+="$v"$'\n'
done <<< "$violations"

vcount=$(echo "$final" | grep -c '.' || true)
if [ "$vcount" -eq 0 ]; then
  report_ok errors "$total"
  exit 0
fi

report_fail errors "$vcount"
echo -n "$final"
exit 1
